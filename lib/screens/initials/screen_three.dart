import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_ml_kit/google_ml_kit.dart';
import 'package:just_audio/just_audio.dart';
// import 'package:loringo_app/screens/initials/screen_four.dart';
import 'package:loringo_app/services/translation/teacher_ui_translations.dart';
import 'package:lottie/lottie.dart';

class ScreenThree extends StatefulWidget {
  final String contentId;
  final String unitId;
  final String lessonId;
  final String activityId;
  final String taskId;
  final Function(bool isCorrect)? onTaskComplete;
  final int currentTaskNumber;
  final int totalTasks;
  final String collectionName;

  const ScreenThree({
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
  State<ScreenThree> createState() => _ScreenThreeState();
}

class _ScreenThreeState extends State<ScreenThree> {
  final AudioPlayer player = AudioPlayer();
  final FlutterTts flutterTts = FlutterTts();
  late OnDeviceTranslator translator;

  static const Color greenPrimary = Color(0xFF4CAF50);

  String _userLang = 'English';
  String subtitle = '';
  String questionEn = '';
  String questionTranslated = '';
  List<String> answerEn = [];
  List<String> answerTranslated = [];
  List<Map<String, String>> shuffledWords = [];
  List<Map<String, String>> selectedWords = [];
  bool showQuestionInSpanish =
      true; // Random mode: true = Q in Spanish, A in English

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
    // TTS language will be set dynamically in _speak method based on mode
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
        answerEn = List<String>.from(taskData['answer'] ?? []);

        // Randomly decide: true = Question in Spanish, Answer in English
        //                  false = Question in English, Answer in Spanish
        showQuestionInSpanish = DateTime.now().millisecondsSinceEpoch % 2 == 0;

        // Translate the question to user's language
        questionTranslated = await translator.translateText(questionEn);

        answerTranslated = [];
        for (final word in answerEn) {
          final translated = await translator.translateText(word);
          answerTranslated.add(translated);
        }
        shuffledWords = [];

        for (var i = 0; i < answerEn.length; i++) {
          shuffledWords.add({
            'en': answerEn[i],
            'translated': answerTranslated[i],
          });
        }
        shuffledWords.shuffle();
        setState(() {});
      }
    } catch (e) {
      throw ("Error fetching or translating task data: $e");
    }
  }

  void _speak(String text) async {
    if (text.isNotEmpty) {
      // Set TTS language based on the mode
      final ttsLang = showQuestionInSpanish
          ? _getTtsCode(translator.targetLanguage)
          : 'en-GB';
      await flutterTts.setLanguage(ttsLang);
      await flutterTts.speak(text);
    }
  }

  void _selectWord(Map<String, String> word) {
    setState(() {
      selectedWords.add(word);
      shuffledWords.remove(word);
    });
  }

  void _removeWord(Map<String, String> word) {
    setState(() {
      shuffledWords.add(word);
      selectedWords.remove(word);
    });
  }

  void _checkAnswer() {
    final selected = showQuestionInSpanish
        ? selectedWords.map((w) => w['en']).toList()
        : selectedWords.map((w) => w['translated']).toList();
    final correct = showQuestionInSpanish ? answerEn : answerTranslated;

    final isCorrect = selected.join(' ') == correct.join(' ');

    _playFeedback(isCorrect);
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
              padding: const EdgeInsets.all(16),
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
                          widget.onTaskComplete!(isCorrect);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: greenPrimary,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 5,
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
                          widget.onTaskComplete!(isCorrect);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 5,
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
          child: shuffledWords.isEmpty && selectedWords.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // header
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

                    // subtitle and hint
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              showQuestionInSpanish
                                  ? questionTranslated
                                  : questionEn,
                              style: const TextStyle(
                                fontSize: 18,
                                color: Colors.black54,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.volume_up,
                              color: greenPrimary,
                              size: 28,
                            ),
                            onPressed: () => _speak(
                              showQuestionInSpanish
                                  ? questionTranslated
                                  : questionEn,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: greenPrimary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: selectedWords.map((word) {
                            return GestureDetector(
                              onTap: () => _removeWord(word),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 14,
                                ),
                                decoration: BoxDecoration(
                                  color: greenPrimary,
                                  borderRadius: BorderRadius.circular(30),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      showQuestionInSpanish
                                          ? word['en']!
                                          : word['translated']!,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 18,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    const Icon(
                                      Icons.close,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.grey.withValues(alpha: 0.2),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          constraints: const BoxConstraints(
                            minHeight: 200,
                            maxHeight: 200,
                          ),
                          child: SingleChildScrollView(
                            child: Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              children: shuffledWords.map((word) {
                                return GestureDetector(
                                  onTap: () => _selectWord(word),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 12,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      border: Border.all(
                                        color: greenPrimary,
                                        width: 2,
                                      ),
                                      borderRadius: BorderRadius.circular(30),
                                    ),
                                    child: Text(
                                      showQuestionInSpanish
                                          ? word['en']!
                                          : word['translated']!,
                                      style: const TextStyle(
                                        color: Colors.black87,
                                        fontSize: 18,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
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
                          onPressed: selectedWords.length == answerEn.length
                              ? _checkAnswer
                              : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: greenPrimary,
                            padding: const EdgeInsets.symmetric(vertical: 18),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            elevation: 5,
                          ),
                          child: Text(
                            TeacherUITranslations.get('check', _userLang),
                            style: const TextStyle(
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
