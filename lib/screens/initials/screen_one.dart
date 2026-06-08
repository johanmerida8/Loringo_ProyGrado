import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/svg.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_ml_kit/google_ml_kit.dart';
import 'package:just_audio/just_audio.dart';
// import 'package:loringo_app/services/translation/teacher_ui_translations.dart';
import 'package:lottie/lottie.dart';

class ScreenOne extends StatefulWidget {
  final String contentId;
  final String unitId;
  final String lessonId;
  final String activityId;
  final String taskId;
  final Function(bool isCorrect)? onTaskComplete;
  final int currentTaskNumber;
  final int totalTasks;
  final String collectionName;

  const ScreenOne({
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
  State<ScreenOne> createState() => _ScreenOneState();
}

class _ScreenOneState extends State<ScreenOne> {
  final FlutterTts flutterTts = FlutterTts();
  final player = AudioPlayer();
  late final OnDeviceTranslator translator;

  String _userLang = 'English';
  String word = '';
  List<Map<String, dynamic>> options = [];
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
        if (taskData != null && taskData['type'] == 'image_select') {
          final data = taskData['data'] as Map<String, dynamic>? ?? {};
          String fetchedWord = data['word'] ?? taskData['question'] ?? '';
          List<dynamic> fetchedOptions = data['options'] ?? [];

          String translatedWord = await translator.translateText(fetchedWord);

          List<Map<String, dynamic>> translatedOptions = fetchedOptions.map((
            option,
          ) {
            return {
              'text': option['text'],
              'image': option['image'],
              'isCorrect': option['isCorrect'],
            };
          }).toList();

          setState(() {
            word = translatedWord;
            options = translatedOptions;
          });
        }
      }
    } catch (e) {
      throw Exception('Error fetching task: $e');
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
    final option = options.firstWhere(
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
                          print('DEBUG ScreenOne: CONTINUE button pressed');
                          Navigator.pop(context); // Close bottom sheet
                          if (widget.onTaskComplete != null) {
                            print(
                              'DEBUG ScreenOne: Calling onTaskComplete callback with isCorrect=$isCorrect',
                            );
                            widget.onTaskComplete!(isCorrect); // Pass result
                          } else {
                            print('DEBUG ScreenOne: No callback, popping back');
                            Navigator.pop(
                              context,
                            ); // Fallback: exit if no callback
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
                          // TeacherUITranslations.get('continueBtnText', _userLang),
                          'Continue',
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
                          print('DEBUG ScreenOne: TRY AGAIN button pressed');
                          Navigator.pop(context); // Close bottom sheet
                          if (widget.onTaskComplete != null) {
                            print(
                              'DEBUG ScreenOne: Calling onTaskComplete callback with isCorrect=$isCorrect',
                            );
                            widget.onTaskComplete!(isCorrect); // Pass wrong result
                          } else {
                            print('DEBUG ScreenOne: No callback, popping back');
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
                          // TeacherUITranslations.get('continueBtnText', _userLang),
                          'Continue',
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
                            onPressed: () => _speak(word),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              word,
                              style: const TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      // TeacherUITranslations.get('selectCorrectImage', _userLang),
                      'Select the correct image',
                      style: const TextStyle(fontSize: 20, color: Colors.black54),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: GridView.builder(
                          itemCount: options.length,
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                mainAxisSpacing: 16,
                                crossAxisSpacing: 16,
                              ),
                          itemBuilder: (context, index) {
                            final option = options[index];
                            final isSelected = selectedOption == option['text'];
                            return GestureDetector(
                              onTap: () => _handleSelection(option['text']),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 300),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? greenPrimary
                                      : Colors.white,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: isSelected
                                        ? greenPrimary
                                        : greyAccent,
                                    width: 4,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black12,
                                      blurRadius: 10,
                                      offset: Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(12.0),
                                    child:
                                        option['image'].toString().endsWith('.svg') &&
                                        !option['image'].toString().contains('f_png')
                                        ? SvgPicture.network(
                                            option['image'],
                                            fit: BoxFit.contain,
                                            placeholderBuilder: (context) =>
                                                const CircularProgressIndicator(),
                                          )
                                        : CachedNetworkImage(
                                            imageUrl: option['image'],
                                            placeholder: (_, __) =>
                                                const CircularProgressIndicator(),
                                            errorWidget: (_, __, ___) =>
                                                const Icon(Icons.error),
                                            fit: BoxFit.contain,
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
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 5,
                          ),
                          child: Text(
                            // TeacherUITranslations.get('check', _userLang),
                            'Check',
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
