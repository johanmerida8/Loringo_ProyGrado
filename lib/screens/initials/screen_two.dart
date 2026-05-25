import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_ml_kit/google_ml_kit.dart';
import 'package:just_audio/just_audio.dart';
// import 'package:loringo_app/screens/initials/screen_three.dart';
import 'package:loringo_app/services/translation/teacher_ui_translations.dart';
import 'package:lottie/lottie.dart';

class ScreenTwo extends StatefulWidget {
  final String contentId;
  final String unitId;
  final String lessonId;
  final String activityId;
  final String taskId;
  final Function(bool isCorrect) onTaskComplete;
  final int currentTaskNumber;
  final int totalTasks;
  final String collectionName;

  const ScreenTwo({
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
  State<ScreenTwo> createState() => _ScreenTwoState();
}

class _ScreenTwoState extends State<ScreenTwo> {
  final AudioPlayer player = AudioPlayer();
  final FlutterTts flutterTts = FlutterTts();

  late OnDeviceTranslator translator;

  String _userLang = 'English';
  String subtitle = '';
  String questionEn = '';
  String questionTranslated = '';
  List<Map<String, dynamic>> options = [];

  String selectedOption = '';
  bool isCorrectAnswerSelected = false;

  static const Color greenPrimary = Color(0xFF4CAF50);

  @override
  void initState() {
    super.initState();
    _setUp();
  }

  Future<void> _setUp() async {
    await _initTranslator();
    await _initializeTts();
    await _fetchTask();
  }

  Future<void> _initTranslator() async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    String userLang = 'Spanish'; // Default language
    
    // Only fetch user language if user is authenticated
    if (userId != null) {
      final userDoc = await FirebaseFirestore.instance
          .collection("users")
          .doc(userId)
          .get();
      
      if (userDoc.exists) {
        userLang = userDoc['language'] ?? 'Spanish';
      }
    }
    _userLang = userLang;
    final targetLang = _mapLanguageToEnum(userLang);

    translator = OnDeviceTranslator(
      sourceLanguage: TranslateLanguage.english,
      targetLanguage: targetLang,
    );
  }

  TranslateLanguage _mapLanguageToEnum(String lang) {
    switch (lang.toLowerCase()) {
      case 'spanish':
        return TranslateLanguage.spanish;
      case 'french':
        return TranslateLanguage.french;
      case 'german':
        return TranslateLanguage.german;
      case 'italian':
        return TranslateLanguage.italian;
      default:
        return TranslateLanguage.spanish;
    }
  }

  Future<void> _initializeTts() async {
    await flutterTts.setLanguage('en-GB');
    await flutterTts.setSpeechRate(0.5);
    await flutterTts.setPitch(1.0);
  }

  String _getTtsCode(TranslateLanguage lang) {
    switch (lang) {
      case TranslateLanguage.spanish:
        return 'es-ES';
      case TranslateLanguage.french:
        return 'fr-FR';
      case TranslateLanguage.german:
        return 'de-DE';
      case TranslateLanguage.italian:
        return 'it-IT';
      default:
        return 'es-ES';
    }
  }

  @override
  void dispose() {
    super.dispose();
    translator.close();
    player.dispose();
    flutterTts.stop();
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
        final data = doc.data() as Map<String, dynamic>;
        final taskData = data['data'] as Map<String, dynamic>? ?? data;

        subtitle = taskData['subtitle'] ?? '';
        questionEn = taskData['question'] ?? '';

        final originalOptions = List<Map<String, dynamic>>.from(
          taskData['options'] ?? [],
        );

        options = [];
        for (var opt in originalOptions) {
          options.add({
            'textEn': opt['text'],
            'isCorrect': opt['isCorrect'] ?? false,
          });
        }
        setState(() {});
      }
    } catch (e) {
      throw Exception('Error fetching or translating task data: $e');
    }
  }

  void _speak(String text) async {
    if (text.isNotEmpty) {
      await flutterTts.speak(text);
    }
  }

  void _handleSelection(String textEn) {
    setState(() {
      selectedOption = textEn;
    });
  }

  void _checkAnswer() {
    if (selectedOption.isEmpty) return;

    final selectedOptionData = options.firstWhere(
      (opt) => opt['textEn'] == selectedOption,
      orElse: () => {},
    );

    final bool isCorrect = selectedOptionData['isCorrect'] == true;
    _playFeedback(isCorrect);

    setState(() {
      isCorrectAnswerSelected = isCorrect;
    });
  }

  void _playFeedback(bool isCorrect) async {
    if (isCorrect) {
      HapticFeedback.mediumImpact();
    } else {
      HapticFeedback.heavyImpact();
    }
    final soundAsset = isCorrect
        ? 'assets/sound/success-2.mp3'
        : 'assets/sound/fail-2.mp3';

    player.setAsset(soundAsset).then((_) => player.play());

    final animation = isCorrect ? 'success' : 'fail';
    _showResultBottomSheet(animation, isCorrect);
  }

  void _showResultBottomSheet(String animationType, bool isCorrect) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) {
        return DraggableScrollableSheet(
          initialChildSize: 0.4,
          maxChildSize: 0.6,
          builder: (_, controller) {
            return Container(
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 20,
                    offset: Offset(0, -5),
                  ),
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Lottie.asset(
                    animationType == 'success'
                        ? 'assets/animation/correct.json'
                        : 'assets/animation/fail.json',
                    height: 150,
                  ),
                  const SizedBox(height: 20),
                  if (isCorrect)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(context);
                          widget.onTaskComplete(isCorrect);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: greenPrimary,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: Text(
                          TeacherUITranslations.get('continueBtnText', _userLang),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                    ),
                  if (!isCorrect)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(context);
                          widget.onTaskComplete(isCorrect);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: Text(
                          TeacherUITranslations.get('continueBtnText', _userLang),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
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
          child: options.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 16,
                      ),
                      child: Row(
                        children: [
                          IconButton(
                            icon: const Icon(
                              Icons.close,
                              color: Colors.black87,
                              size: 28,
                            ),
                            onPressed: () => Navigator.pop(context),
                          ),
                          Expanded(
                            child: ClipRRect(
                              borderRadius: const BorderRadius.all(
                                Radius.circular(30),
                              ),
                              child: LinearProgressIndicator(
                                value:
                                    (widget.currentTaskNumber + 1) /
                                    widget.totalTasks,
                                backgroundColor: Colors.blueGrey,
                                valueColor: const AlwaysStoppedAnimation<Color>(
                                  greenPrimary,
                                ),
                                minHeight: 8,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 20),
                      child: Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        children: [
                          IconButton(
                            onPressed: () => _speak(questionEn),
                            icon: const Icon(Icons.volume_up),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.grey.shade300,
                                  width: 1.5,
                                ),
                              ),
                              child: Text(
                                questionEn,
                                style: const TextStyle(
                                  fontSize: 18,
                                  color: Colors.black87,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: ListView.builder(
                          itemCount: options.length,
                          itemBuilder: (context, index) {
                            final option = options[index];
                            final isSelected =
                                selectedOption == option['textEn'];
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: GestureDetector(
                                onTap: () =>
                                    _handleSelection(option['textEn'] ?? ''),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 300),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                    vertical: 16,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? greenPrimary
                                        : Colors.white,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: isSelected
                                          ? greenPrimary
                                          : Colors.grey.shade300,
                                      width: 2,
                                    ),
                                  ),
                                  child: Text(
                                    option['textEn'] as String? ?? '',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: isSelected
                                          ? Colors.white
                                          : Colors.black87,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 20,
                      ),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: selectedOption.isEmpty
                              ? null
                              : _checkAnswer,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: greenPrimary,
                            padding: const EdgeInsets.symmetric(vertical: 18),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: Text(
                            TeacherUITranslations.get('check', _userLang),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
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
}
