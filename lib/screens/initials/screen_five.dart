import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/svg.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_ml_kit/google_ml_kit.dart';
import 'package:just_audio/just_audio.dart';
import 'package:loringo_app/services/translation/teacher_ui_translations.dart';
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
  late final OnDeviceTranslator translator;

  String _userLang = 'English';
  String imageUrl = '';
  String question = '';
  List<Map<String, dynamic>> textOptions = [];
  String selectedOption = '';

  static const Color greenPrimary = Color(0xFF4CAF50);
  static const Color greyAccent = Color(0xFF81C784);

  @override
  void initState() {
    super.initState();
    _setUp();
  }

  Future<void> _setUp() async {
    await _initTranslator();
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

  @override
  void dispose() {
    super.dispose();
    translator.close();
    player.dispose();
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
          String fetchedImage = data['image'] ?? '';
          String fetchedQuestion =
              taskData['question']?.isNotEmpty == true
                  ? taskData['question']
                  : 'Select the correct phrase';
          List<dynamic> fetchedOptions = data['options'] ?? [];

          // Translate question
          String translatedQuestion = await translator.translateText(
            fetchedQuestion,
          );

          // Keep text options in English (don't translate)
          List<Map<String, dynamic>> optionsList = [];
          for (var option in fetchedOptions) {
            optionsList.add({
              'text': option['text'],
              'isCorrect': option['isCorrect'],
            });
          }

          setState(() {
            imageUrl = fetchedImage;
            question = translatedQuestion;
            textOptions = optionsList;
          });
        }
      }
    } catch (e) {
      print('Error fetching task: $e');
    }
  }

  void _speak(String text) async {
    final targetLang = translator.targetLanguage;

    String ttsLang = 'es';
    switch (targetLang) {
      case TranslateLanguage.spanish:
        ttsLang = 'es';
        break;
      case TranslateLanguage.french:
        ttsLang = 'fr';
        break;
      case TranslateLanguage.german:
        ttsLang = 'de';
        break;
      case TranslateLanguage.italian:
        ttsLang = 'it';
        break;
      default:
        ttsLang = 'es';
    }

    await flutterTts.setLanguage(ttsLang);
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
                          print('DEBUG ScreenFive: CONTINUE button pressed');
                          Navigator.pop(context); // Close bottom sheet
                          if (widget.onTaskComplete != null) {
                            print(
                              'DEBUG ScreenFive: Calling onTaskComplete callback with isCorrect=$isCorrect',
                            );
                            widget.onTaskComplete!(isCorrect);
                          } else {
                            print(
                              'DEBUG ScreenFive: No callback, popping back',
                            );
                            Navigator.pop(context);
                          }
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
                          print('DEBUG ScreenFive: CONTINUE button pressed (wrong answer)');
                          Navigator.pop(context); // Close bottom sheet
                          if (widget.onTaskComplete != null) {
                            print(
                              'DEBUG ScreenFive: Calling onTaskComplete callback with isCorrect=$isCorrect',
                            );
                            widget.onTaskComplete!(isCorrect);
                          } else {
                            print(
                              'DEBUG ScreenFive: No callback, popping back',
                            );
                            Navigator.pop(context);
                          }
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
          child: imageUrl.isEmpty || textOptions.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    // Progress bar
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 16,
                      ),
                      child: Row(
                        children: [
                          IconButton(
                            onPressed: () {
                              Navigator.pop(context);
                            },
                            icon: const Icon(
                              Icons.close,
                              color: Colors.black87,
                              size: 28,
                            ),
                          ),
                          Expanded(
                            child: ClipRRect(
                              borderRadius: const BorderRadius.all(
                                Radius.circular(30),
                              ),
                              child: LinearProgressIndicator(
                                value:
                                    widget.currentTaskNumber /
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

                    // Question with audio
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        children: [
                          IconButton(
                            icon: const Icon(
                              Icons.volume_up,
                              color: Colors.black87,
                              size: 28,
                            ),
                            onPressed: () => _speak(question),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              question,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Scrollable content
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          children: [
                            const SizedBox(height: 20),

                            // Main Image
                            Container(
                              margin: const EdgeInsets.symmetric(
                                horizontal: 40,
                              ),
                              height: 250,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black12,
                                    blurRadius: 15,
                                    offset: const Offset(0, 5),
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(20),
                                child: imageUrl.endsWith('.svg') && !imageUrl.contains('f_png')
                                    ? SvgPicture.network(
                                        imageUrl,
                                        fit: BoxFit.contain,
                                        placeholderBuilder: (context) =>
                                            const Center(
                                              child:
                                                  CircularProgressIndicator(),
                                            ),
                                      )
                                    : CachedNetworkImage(
                                        imageUrl: imageUrl,
                                        fit: BoxFit.contain,
                                        placeholder: (_, __) => const Center(
                                          child: CircularProgressIndicator(),
                                        ),
                                        errorWidget: (_, __, ___) =>
                                            const Icon(Icons.error, size: 50),
                                      ),
                              ),
                            ),

                            const SizedBox(height: 24),

                            Text(
                              TeacherUITranslations.get('selectCorrectPhrase', _userLang),
                              style: const TextStyle(
                                fontSize: 18,
                                color: Colors.black54,
                              ),
                            ),

                            const SizedBox(height: 16),

                            // Text options
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                              ),
                              child: Column(
                                children: List.generate(textOptions.length, (
                                  index,
                                ) {
                                  final option = textOptions[index];
                                  final isSelected =
                                      selectedOption == option['text'];

                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: GestureDetector(
                                      onTap: () =>
                                          _handleSelection(option['text']),
                                      child: AnimatedContainer(
                                        duration: const Duration(
                                          milliseconds: 300,
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 20,
                                          vertical: 20,
                                        ),
                                        decoration: BoxDecoration(
                                          color: isSelected
                                              ? greenPrimary
                                              : Colors.white,
                                          borderRadius: BorderRadius.circular(
                                            15,
                                          ),
                                          border: Border.all(
                                            color: isSelected
                                                ? greenPrimary
                                                : greyAccent,
                                            width: 3,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black12,
                                              blurRadius: 8,
                                              offset: const Offset(0, 3),
                                            ),
                                          ],
                                        ),
                                        child: Row(
                                          children: [
                                            Container(
                                              width: 30,
                                              height: 30,
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                border: Border.all(
                                                  color: isSelected
                                                      ? Colors.white
                                                      : greyAccent,
                                                  width: 2,
                                                ),
                                                color: isSelected
                                                    ? Colors.white
                                                    : Colors.transparent,
                                              ),
                                              child: isSelected
                                                  ? const Icon(
                                                      Icons.check,
                                                      size: 18,
                                                      color: greenPrimary,
                                                    )
                                                  : null,
                                            ),
                                            const SizedBox(width: 16),
                                            Expanded(
                                              child: Text(
                                                option['text'],
                                                style: TextStyle(
                                                  color: isSelected
                                                      ? Colors.white
                                                      : Colors.black87,
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
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

                    // Check button
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
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 5,
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
