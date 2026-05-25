import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:loringo_app/screens/initials/activity_play_screen.dart';
import 'package:loringo_app/screens/initials/quiz_play_screen.dart';
import 'package:loringo_app/screens/initials/leaderboard_screen.dart';
import 'package:loringo_app/services/auth/auth_gate.dart';
import 'package:loringo_app/screens/initials/profile_screen.dart';
import 'package:lottie/lottie.dart';

class LevelScreen extends StatefulWidget {
  const LevelScreen({super.key});

  static const Color greenPrimary = Color(0xFF4CAF50);
  static const Color greenAccent = Color(0xFF81C784);
  static const backgroundGradient = LinearGradient(
    colors: [Color(0xFFE8F5E9), Colors.white],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  @override
  State<LevelScreen> createState() => _LevelScreenState();
}

class _LevelScreenState extends State<LevelScreen> {
  int _currentIndex = 0;

  final List<String> _languages = [
    'Spanish',
    'English',
    'French',
    'German',
    'Italian',
  ];
  Future<List<Map<String, dynamic>>> _loadAllActivities() async {
    try {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      List<Map<String, dynamic>> allItems = [];

      // Get user progress (completed activities and quizzes)
      Set<String> completedActivities = {};
      Map<String, dynamic> completedQuizzes = {};
      if (userId != null) {
        final activityProgressDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .collection('progress')
            .doc('activities')
            .get();

        if (activityProgressDoc.exists) {
          final data = activityProgressDoc.data();
          completedActivities = Set<String>.from(data?['completed'] ?? []);
        }

        final quizProgressDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .collection('progress')
            .doc('quizzes')
            .get();

        if (quizProgressDoc.exists) {
          completedQuizzes = quizProgressDoc.data() ?? {};
        }
      }

      // Get all content
      final contentSnapshot = await FirebaseFirestore.instance
          .collection('content')
          .orderBy('order')
          .get();

      for (var contentDoc in contentSnapshot.docs) {
        final contentId = contentDoc.id;

        // Get all units in this content
        final unitsSnapshot = await FirebaseFirestore.instance
            .collection('content')
            .doc(contentId)
            .collection('units')
            .orderBy('order')
            .get();

        for (var unitDoc in unitsSnapshot.docs) {
          final unitId = unitDoc.id;
          final unitData = unitDoc.data();
          final isUnitLocked = unitData['locked'] ?? false;

          // Skip locked units
          if (isUnitLocked) continue;

          // Get all lessons in this unit
          final lessonsSnapshot = await FirebaseFirestore.instance
              .collection('content')
              .doc(contentId)
              .collection('units')
              .doc(unitId)
              .collection('lessons')
              .orderBy('order')
              .get();

          // Track unit activities for quiz unlock logic
          List<String> unitActivityIds = [];
          int unitActivitiesCompleted = 0;

          for (var lessonDoc in lessonsSnapshot.docs) {
            final lessonId = lessonDoc.id;
            final lessonData = lessonDoc.data();

            // Get all activities in this lesson
            final activitiesSnapshot = await FirebaseFirestore.instance
                .collection('content')
                .doc(contentId)
                .collection('units')
                .doc(unitId)
                .collection('lessons')
                .doc(lessonId)
                .collection('activities')
                .orderBy('order')
                .get();

            for (var activityDoc in activitiesSnapshot.docs) {
              final activityData = activityDoc.data();
              final activityId = activityDoc.id;
              final requiredActivityId = activityData['requiredActivityId'];

              unitActivityIds.add(activityId);
              if (completedActivities.contains(activityId)) {
                unitActivitiesCompleted++;
              }

              // Check if activity is unlocked
              bool isUnlocked = true;
              if (requiredActivityId != null && requiredActivityId.isNotEmpty) {
                isUnlocked = completedActivities.contains(requiredActivityId);
              }

              allItems.add({
                'type': 'activity',
                'contentId': contentId,
                'unitId': unitId,
                'lessonId': lessonId,
                'activityId': activityId,
                'title': activityData['title'] ?? 'Untitled Activity',
                'order': activityData['order'] ?? 0,
                'isUnlocked': isUnlocked,
                'requiredActivityId': requiredActivityId,
              });
            }

            // Get quizzes for this lesson
            final quizzesSnapshot = await FirebaseFirestore.instance
                .collection('content')
                .doc(contentId)
                .collection('units')
                .doc(unitId)
                .collection('lessons')
                .doc(lessonId)
                .collection('quizzes')
                .get();

            // Add lesson quizzes at the end of lesson activities
            for (var quizDoc in quizzesSnapshot.docs) {
              final quizData = quizDoc.data();
              final quizId = quizDoc.id;

              // Quiz is unlocked if all unit activities are completed
              final bool isQuizUnlocked =
                  unitActivitiesCompleted == unitActivityIds.length &&
                  unitActivityIds.isNotEmpty;

              // Check if quiz is completed
              final bool isCompleted = completedQuizzes.containsKey(quizId);
              final int stars = isCompleted
                  ? (completedQuizzes[quizId]['stars'] ?? 0)
                  : 0;

              allItems.add({
                'type': 'quiz',
                'contentId': contentId,
                'unitId': unitId,
                'lessonId': lessonId,
                'quizId': quizId,
                'title': quizData['title'] ?? 'Unit Quiz',
                'description':
                    quizData['description'] ?? 'Complete to unlock next unit',
                'isUnlocked': isQuizUnlocked,
                'isCompleted': isCompleted,
                'stars': stars,
              });
            }
          }


        }
      }

      return allItems;
    } catch (e) {
      print('Error loading activities and quizzes: $e');
      return [];
    }
  }

  Future<void> _changeLanguage() async {
    final userId = FirebaseAuth.instance.currentUser?.uid;

    String? selectedLanguage = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return SimpleDialog(
          title: const Text('Select Language'),
          children: _languages.map((lang) {
            return SimpleDialogOption(
              onPressed: () {
                Navigator.pop(context, lang);
              },
              child: Text(lang),
            );
          }).toList(),
        );
      },
    );

    if (selectedLanguage != null) {
      await FirebaseFirestore.instance.collection('users').doc(userId).update({
        'language': selectedLanguage,
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Language changed to $selectedLanguage')),
      );
    }
  }

  String _getStarDisplay(int stars) {
    switch (stars) {
      case 3:
        return '⭐⭐⭐';
      case 2:
        return '⭐⭐';
      case 1:
        return '⭐';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final userId = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LevelScreen.backgroundGradient,
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                child: Row(
                  children: [
                    const Text(
                      "Loringo",
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: LevelScreen.greenPrimary,
                      ),
                    ),
                    const Spacer(),
                    PopupMenuButton<String>(
                      icon: const Icon(
                        Icons.settings,
                        color: LevelScreen.greenPrimary,
                      ),
                      onSelected: (value) async {
                        if (value == 'language') {
                          await _changeLanguage();
                        } else if (value == 'logout') {
                          await FirebaseAuth.instance.signOut();
                          if (context.mounted) {
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const AuthGate(),
                              ),
                            );
                          }
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'language',
                          child: ListTile(
                            leading: Icon(
                              Icons.language,
                              color: LevelScreen.greenPrimary,
                            ),
                            title: Text('Change Language'),
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'logout',
                          child: ListTile(
                            leading: Icon(
                              Icons.logout,
                              color: Colors.redAccent,
                            ),
                            title: Text('Logout'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              StreamBuilder<DocumentSnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('users')
                    .doc(userId)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const CircularProgressIndicator();
                  }

                  final userData = snapshot.data!;
                  final email = userData['email'] ?? 'User';
                  final name = email.split('@')[0];
                  final streak = userData['streak'] ?? 0;
                  final language = userData['language'] ?? 'English';

                  return Container(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black12,
                          blurRadius: 10,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        const CircleAvatar(
                          radius: 30,
                          backgroundImage: AssetImage('assets/images/loro.png'),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Text(
                                'Hello, $name!',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                "Learning: $language",
                                style: const TextStyle(
                                  fontSize: 16,
                                  color: Colors.black54,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFFF8A65), Color(0xFFFF7043)],
                            ),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            children: [
                              Text(
                                "🔥 $streak",
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(width: 6),
                              const Text(
                                "Days",
                                style: TextStyle(color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: FutureBuilder<List<Map<String, dynamic>>>(
                    future: _loadAllActivities(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final activities = snapshot.data!;

                      if (activities.isEmpty) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(32.0),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.assignment_rounded,
                                  size: 100,
                                  color: Color(0xFF4CAF50),
                                ),
                                SizedBox(height: 24),
                                Text(
                                  'No Activities Available',
                                  style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF4CAF50),
                                  ),
                                ),
                                SizedBox(height: 12),
                                Text(
                                  'Contact your teacher to add learning activities',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }

                      return SingleChildScrollView(
                        reverse: true,
                        padding: const EdgeInsets.symmetric(vertical: 60),
                        child: Column(
                          children: activities.asMap().entries.map((entry) {
                            final index = entry.key;
                            final item = entry.value;
                            final bool isLeft = index % 2 == 0;
                            final bool isUnlocked = item['isUnlocked'] ?? false;
                            final String itemType = item['type'] ?? 'activity';
                            final bool isQuiz = itemType == 'quiz';
                            final bool isCompleted =
                                item['isCompleted'] ?? false;
                            final int stars = item['stars'] ?? 0;

                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 28),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                mainAxisAlignment: isLeft
                                    ? MainAxisAlignment.start
                                    : MainAxisAlignment.end,
                                children: [
                                  if (!isLeft)
                                    Lottie.asset(
                                      'assets/animation/animation.json',
                                      width: 100,
                                      height: 100,
                                    ),
                                  Column(
                                    children: [
                                      GestureDetector(
                                        onTap: isUnlocked
                                            ? () {
                                                if (isQuiz) {
                                                  Navigator.push(
                                                    context,
                                                    MaterialPageRoute(
                                                      builder: (_) =>
                                                          QuizPlayScreen(
                                                            contentId:
                                                                item['contentId'],
                                                            unitId:
                                                                item['unitId'],
                                                            lessonId:
                                                                item['lessonId'],
                                                            quizId:
                                                                item['quizId'],
                                                            quizTitle:
                                                                item['title'],
                                                          ),
                                                    ),
                                                  );
                                                } else {
                                                  Navigator.push(
                                                    context,
                                                    MaterialPageRoute(
                                                      builder: (_) =>
                                                          ActivityPlayScreen(
                                                            contentId:
                                                                item['contentId'],
                                                            unitId:
                                                                item['unitId'],
                                                            lessonId:
                                                                item['lessonId'] ?? '',
                                                            activityId:
                                                                item['activityId'],
                                                            activityTitle:
                                                                item['title'],
                                                          ),
                                                    ),
                                                  );
                                                }
                                              }
                                            : null,
                                        child: AnimatedContainer(
                                          duration: const Duration(
                                            milliseconds: 300,
                                          ),
                                          margin: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                          ),
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            gradient: isUnlocked
                                                ? (isQuiz
                                                      ? const LinearGradient(
                                                          colors: [
                                                            Color(0xFFFFB74D),
                                                            Color(0xFFFF9800),
                                                          ],
                                                        )
                                                      : const LinearGradient(
                                                          colors: [
                                                            LevelScreen
                                                                .greenPrimary,
                                                            LevelScreen
                                                                .greenAccent,
                                                          ],
                                                        ))
                                                : LinearGradient(
                                                    colors: [
                                                      Colors.grey[400]!,
                                                      Colors.grey[600]!,
                                                    ],
                                                  ),
                                            border: Border.all(
                                              color: Colors.white,
                                              width: 4,
                                            ),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black.withValues(
                                                  alpha: 0.15,
                                                ),
                                                blurRadius: 12,
                                                offset: const Offset(0, 5),
                                              ),
                                            ],
                                          ),
                                          width: 80,
                                          height: 80,
                                          child: Center(
                                            child: Column(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                Icon(
                                                  isUnlocked
                                                      ? (isQuiz
                                                            ? Icons.quiz
                                                            : Icons.star)
                                                      : Icons.lock,
                                                  color: Colors.white,
                                                  size: 28,
                                                ),
                                                const SizedBox(height: 4),
                                                if (isQuiz && isCompleted)
                                                  Text(
                                                    _getStarDisplay(stars),
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 16,
                                                    ),
                                                  )
                                                else
                                                  Text(
                                                    isQuiz
                                                        ? 'Quiz'
                                                        : 'Level ${index + 1}',
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        item['title'],
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: isUnlocked
                                              ? Colors.black87
                                              : Colors.grey[600],
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (isLeft)
                                    Lottie.asset(
                                      'assets/animation/animation3.json',
                                      width: 100,
                                      height: 100,
                                    ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: Colors.white,
        elevation: 12,
        currentIndex: _currentIndex,
        selectedItemColor: Colors.grey,
        unselectedItemColor: Colors.grey,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
          if (index == 1) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const LeaderboardScreen()),
            );
          } else if (index == 2) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ProfileScreen()),
            );
          }
        },
        items: [
          BottomNavigationBarItem(
            icon: SizedBox(
              width: 24,
              height: 24,
              child: Image.asset('assets/avatars/home.png'),
            ),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: SizedBox(
              width: 24,
              height: 24,
              child: Image.asset('assets/avatars/rank.png'),
            ),
            label: 'Leaderboard',
          ),
          BottomNavigationBarItem(
            icon: SizedBox(
              width: 24,
              height: 24,
              child: Image.asset('assets/avatars/avatar.png'),
            ),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
