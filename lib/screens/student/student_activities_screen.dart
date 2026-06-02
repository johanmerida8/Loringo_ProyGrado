import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:loringo_app/screens/initials/activity_play_screen.dart';
import 'package:loringo_app/screens/initials/quiz_play_screen.dart';
import 'package:lottie/lottie.dart';

/// Student Activities Screen
/// Shows activities and quizzes assigned to the student's group
class StudentActivitiesScreen extends StatefulWidget {
  final String studentId;
  final String studentName;

  const StudentActivitiesScreen({
    super.key,
    required this.studentId,
    required this.studentName,
  });

  @override
  State<StudentActivitiesScreen> createState() =>
      _StudentActivitiesScreenState();
}

class _StudentActivitiesScreenState extends State<StudentActivitiesScreen> {
  Future<List<Map<String, dynamic>>> _loadAssignedContent() async {
    try {
      List<Map<String, dynamic>> allItems = [];

      // Get student's group
      final studentDoc = await FirebaseFirestore.instance
          .collection('students')
          .doc(widget.studentId)
          .get();

      if (!studentDoc.exists) {
        return [];
      }

      final studentData = studentDoc.data();
      final groupId = studentData?['groupId'] as String?;

      if (groupId == null) {
        return [];
      }

      // Get approved content assigned to this group
      final contentSnap = await FirebaseFirestore.instance
          .collection('content')
          .where('assignedTo', arrayContains: groupId)
          .where('status', isEqualTo: 'approved')
          .get();

      // Sort by order
      final contentDocs = contentSnap.docs.toList()
        ..sort((a, b) {
          final ao = (a.data()['order'] as num? ?? 0).toInt();
          final bo = (b.data()['order'] as num? ?? 0).toInt();
          return ao.compareTo(bo);
        });

      for (final contentDoc in contentDocs) {
        final contentId = contentDoc.id;

        final unitsSnap = await FirebaseFirestore.instance
            .collection('content')
            .doc(contentId)
            .collection('units')
            .orderBy('order')
            .get();

        for (final unitDoc in unitsSnap.docs) {
          final unitId = unitDoc.id;

          final lessonsSnap = await FirebaseFirestore.instance
              .collection('content')
              .doc(contentId)
              .collection('units')
              .doc(unitId)
              .collection('lessons')
              .orderBy('order')
              .get();

          for (final lessonDoc in lessonsSnap.docs) {
            final lessonId = lessonDoc.id;

            final activitiesSnap = await FirebaseFirestore.instance
                .collection('content')
                .doc(contentId)
                .collection('units')
                .doc(unitId)
                .collection('lessons')
                .doc(lessonId)
                .collection('activities')
                .orderBy('order')
                .get();

            for (final activityDoc in activitiesSnap.docs) {
              final activityData = activityDoc.data();
              allItems.add({
                'type': 'activity',
                'contentId': contentId,
                'unitId': unitId,
                'lessonId': lessonId,
                'activityId': activityDoc.id,
                'title': activityData['title'] ?? 'Untitled Activity',
                'order': activityData['order'] ?? 0,
                'isUnlocked': true,
                'isCompleted': false,
                'requiredActivityId': null,
                'bonusXP': null,
                'deadline': null,
              });
            }

            final quizzesSnap = await FirebaseFirestore.instance
                .collection('content')
                .doc(contentId)
                .collection('units')
                .doc(unitId)
                .collection('lessons')
                .doc(lessonId)
                .collection('quizzes')
                .get();

            for (final quizDoc in quizzesSnap.docs) {
              final quizData = quizDoc.data();
              allItems.add({
                'type': 'quiz',
                'contentId': contentId,
                'unitId': unitId,
                'lessonId': lessonId,
                'quizId': quizDoc.id,
                'title': quizData['title'] ?? 'Unit Quiz',
                'description': quizData['description'] ?? '',
                'isUnlocked': true,
                'isCompleted': false,
                'stars': 0,
                'bonusXP': null,
                'deadline': null,
              });
            }
          }
        }
      }

      return allItems;
    } catch (e) {
      print('Error loading assigned content: $e');
      return [];
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
    return Scaffold(
      backgroundColor: const Color(0xFFFAEDCA),
      appBar: AppBar(
        backgroundColor: const Color(0xFF4CAF50),
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back, color: Colors.white),
        ),
        title: const Text(
          'My Activities',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 22,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Student info header
            Container(
              margin: const EdgeInsets.all(20),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF4CAF50), Color(0xFF81C784)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF4CAF50).withOpacity(0.3),
                    offset: const Offset(0, 4),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.school_rounded,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.studentName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Keep learning! 🚀',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Activities list
            Expanded(
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _loadAssignedContent(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.assignment_outlined,
                              size: 100,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 24),
                            Text(
                              'No Activities Yet',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey[700],
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Your teacher will assign activities soon',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  final activities = snapshot.data!;

                  return SingleChildScrollView(
                    reverse: true,
                    padding: const EdgeInsets.symmetric(
                      vertical: 40,
                      horizontal: 20,
                    ),
                    child: Column(
                      children: activities.asMap().entries.map((entry) {
                        final index = entry.key;
                        final item = entry.value;
                        final bool isLeft = index % 2 == 0;
                        final bool isUnlocked = item['isUnlocked'] ?? false;
                        final String itemType = item['type'] ?? 'activity';
                        final bool isQuiz = itemType == 'quiz';
                        final bool isCompleted = item['isCompleted'] ?? false;
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
                                                    unitId: item['unitId'],
                                                    lessonId: item['lessonId'],
                                                    quizId: item['quizId'],
                                                    quizTitle: item['title'],
                                                    collectionName: 'content',
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
                                                    unitId: item['unitId'],
                                                    lessonId: item['lessonId'],
                                                    activityId:
                                                        item['activityId'],
                                                    activityTitle:
                                                        item['title'],
                                                    collectionName: 'content',
                                                  ),
                                                ),
                                              );
                                            }
                                          }
                                        : null,
                                    child: AnimatedContainer(
                                      duration:
                                          const Duration(milliseconds: 300),
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
                                                      Color(0xFF4CAF50),
                                                      Color(0xFF81C784),
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
                                            color:
                                                Colors.black.withOpacity(0.15),
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
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 12,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  SizedBox(
                                    width: 120,
                                    child: Text(
                                      item['title'],
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: isUnlocked
                                            ? Colors.black87
                                            : Colors.grey[600],
                                      ),
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
          ],
        ),
      ),
    );
  }
}
