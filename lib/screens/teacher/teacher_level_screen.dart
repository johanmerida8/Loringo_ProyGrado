import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:loringo_app/screens/initials/activity_play_screen.dart';
import 'package:loringo_app/screens/initials/quiz_lesson_play_screen.dart';
import 'package:loringo_app/screens/initials/quiz_unit_play_screen.dart';
import 'package:loringo_app/screens/teacher/task_list_screen.dart';
import 'package:lottie/lottie.dart';

class TeacherLevelScreen extends StatefulWidget {
  final String groupId;
  final String groupName;
  final bool embedded;
  final List<Map<String, dynamic>>? preloadedItems;
  final void Function(List<Map<String, dynamic>>)? onLoaded;

  const TeacherLevelScreen({
    super.key,
    required this.groupId,
    required this.groupName,
    this.embedded = false,
    this.preloadedItems,
    this.onLoaded,
  });

  @override
  State<TeacherLevelScreen> createState() => _TeacherLevelScreenState();
}

class _TeacherLevelScreenState extends State<TeacherLevelScreen> {
  static const Color greenPrimary = Color(0xFF4CAF50);
  static const Color greenAccent = Color(0xFF81C784);

  static const List<String> _unitMascots = [
    'assets/animation/animation.json',
    'assets/animation/animation3.json',
    'assets/animation/animation1.json',
    'assets/animation/animation2.json',
  ];

  late Future<List<Map<String, dynamic>>> _contentFuture;

  @override
  void initState() {
    super.initState();
    if (widget.preloadedItems != null) {
      _contentFuture = Future.value(widget.preloadedItems);
    } else {
      _contentFuture = _loadGroupContent().then((items) {
        widget.onLoaded?.call(items);
        return items;
      });
    }
  }

  Future<T?> _pushWithTransition<T>(Widget page) {
    return Navigator.push<T>(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => page,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(0.0, 0.05); // slight slide up
          const end = Offset.zero;
          const curve = Curves.easeInOutCubic;

          var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
          var offsetAnimation = animation.drive(tween);

          var fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeIn),
          );

          return FadeTransition(
            opacity: fadeAnimation,
            child: SlideTransition(position: offsetAnimation, child: child),
          );
        },
        transitionDuration: const Duration(milliseconds: 400),
        reverseTransitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _loadGroupContent() async {
    try {
      // Load approved content for this group
      final contentSnap = await FirebaseFirestore.instance
          .collection('content')
          .where('assignedTo', arrayContains: widget.groupId)
          .where('status', isEqualTo: 'approved')
          .get();

      final contentDocs = contentSnap.docs
        ..sort((a, b) {
          final ao = (a.data()['order'] ?? 0) as int;
          final bo = (b.data()['order'] ?? 0) as int;
          return ao.compareTo(bo);
        });

      final allUnitsSnaps = await Future.wait(
        contentDocs.map((cd) => FirebaseFirestore.instance
            .collection('content')
            .doc(cd.id)
            .collection('units')
            .orderBy('order')
            .get()),
      );

      final items = <Map<String, dynamic>>[];

      for (int ci = 0; ci < contentDocs.length; ci++) {
        final contentDoc = contentDocs[ci];
        final contentId = contentDoc.id;
        final contentData = contentDoc.data();

        items.add({
          'type': 'content_header',
          'title': contentData['title'] ?? 'Untitled Content',
          'contentId': contentId,
        });

        final unitDocs = allUnitsSnaps[ci].docs;

        // ✅ Load unit quizzes from root 'quizzes' collection
        final unitQuizzesMap = <String, List<QueryDocumentSnapshot>>{};
        final unitQuizzesSnap = await FirebaseFirestore.instance
            .collection('quizzes')
            .where('type', isEqualTo: 'unit')
            .where('contentId', isEqualTo: contentId)
            .get();
        
        for (final quizDoc in unitQuizzesSnap.docs) {
          final quizData = quizDoc.data() as Map<String, dynamic>;
          final unitId = quizData['unitId'] as String;
          unitQuizzesMap.putIfAbsent(unitId, () => []).add(quizDoc);
        }

        final perUnitResults = await Future.wait(
          unitDocs.map((ud) => Future.wait([
                FirebaseFirestore.instance
                    .collection('content')
                    .doc(contentId)
                    .collection('units')
                    .doc(ud.id)
                    .collection('lessons')
                    .orderBy('order')
                    .get(),
                // ✅ Load lesson quizzes from root collection
                FirebaseFirestore.instance
                    .collection('quizzes')
                    .where('type', isEqualTo: 'lesson')
                    .where('contentId', isEqualTo: contentId)
                    .where('unitId', isEqualTo: ud.id)
                    .get(),
              ])),
        );

        int unitIndex = 0;
        for (int ui = 0; ui < unitDocs.length; ui++) {
          final unitDoc = unitDocs[ui];
          final unitId = unitDoc.id;
          final unitData = unitDoc.data();
          unitIndex++;

          items.add({
            'type': 'unit_header',
            'unitTitle': unitData['title'] ?? 'Untitled Unit',
            'unitIndex': unitIndex,
            'contentId': contentId,
            'unitId': unitId,
          });

          final lessonDocs = perUnitResults[ui][0].docs;
          final lessonQuizzes = perUnitResults[ui][1].docs;

          final perLessonResults = await Future.wait(
            lessonDocs.map((ld) => FirebaseFirestore.instance
                .collection('content')
                .doc(contentId)
                .collection('units')
                .doc(unitId)
                .collection('lessons')
                .doc(ld.id)
                .collection('activities')
                .orderBy('order')
                .get()),
          );

          for (int li = 0; li < lessonDocs.length; li++) {
            final lessonDoc = lessonDocs[li];
            final lessonId = lessonDoc.id;
            final lessonData = lessonDoc.data();

            items.add({
              'type': 'lesson_header',
              'lessonTitle': lessonData['title'] ?? 'Untitled Lesson',
              'contentId': contentId,
              'unitId': unitId,
              'lessonId': lessonId,
            });

            // Activities
            for (final activityDoc in perLessonResults[li].docs) {
              final d = activityDoc.data();
              items.add({
                'type': 'activity',
                'contentId': contentId,
                'unitId': unitId,
                'lessonId': lessonId,
                'activityId': activityDoc.id,
                'title': d['title'] ?? 'Untitled Activity',
                'order': d['order'] ?? 0,
                'xpBase': d['xpBase'] ?? 0,
                'difficulty': d['difficulty'] ?? 'easy',
              });
            }
          }

          // ✅ Add lesson quizzes (filtered by lessonId)
          for (final quizDoc in lessonQuizzes) {
            final quizData = quizDoc.data() as Map<String, dynamic>;
            final quizLessonId = quizData['lessonId'] as String?;
            if (quizLessonId != null) {
              items.add({
                'type': 'quiz',
                'contentId': contentId,
                'unitId': unitId,
                'lessonId': quizLessonId,
                'quizId': quizDoc.id,
                'title': quizData['title'] ?? 'Untitled Quiz',
                'quizType': 'lesson_quiz',
                'xpReward': quizData['xpReward'] ?? 0,
                'questionCount': (quizData['questionIds'] as List?)?.length ?? 0,
              });
            }
          }

          // ✅ Add unit quizzes
          final unitQuizzes = unitQuizzesMap[unitId] ?? [];
          for (final quizDoc in unitQuizzes) {
            final quizData = quizDoc.data() as Map<String, dynamic>;
            
            items.add({
              'type': 'quiz',
              'contentId': contentId,
              'unitId': unitId,
              'lessonId': '',
              'quizId': quizDoc.id,
              'title': quizData['title'] ?? 'Unit Quiz',
              'quizType': 'unit_test',
              'xpReward': quizData['xpReward'] ?? 0,
              'questionCount': quizData['totalQuestions'] ?? 0,
            });
          }
        }
      }

      return items;
    } catch (e) {
      debugPrint('Error loading content: $e');
      return [];
    }
  }

  Color _difficultyColor(String diff) {
    switch (diff) {
      case 'easy':   return Colors.green;
      case 'medium': return Colors.orange;
      case 'hard':   return Colors.red;
      default:       return Colors.grey;
    }
  }

  void _showActivityDialog(Map<String, dynamic> item) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(item['title'], style: const TextStyle(fontWeight: FontWeight.bold)),
        content: Wrap(spacing: 8, runSpacing: 8, children: [
          _chip(Icons.star, '${item['xpBase']} XP', Colors.amber),
          _chip(Icons.speed, (item['difficulty'] as String).toUpperCase(),
              _difficultyColor(item['difficulty'])),
          _chip(Icons.reorder, 'Order: ${item['order']}', Colors.blue),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(
                builder: (_) => PersonalizedTaskListScreen(
                  groupId: widget.groupId,
                  contentId: item['contentId'],
                  unitId: item['unitId'],
                  lessonId: item['lessonId'],
                  activityId: item['activityId'],
                  activityTitle: item['title'],
                  groupColor: greenPrimary,
                ),
              ));
            },
            icon: const Icon(Icons.list_alt, size: 18),
            label: const Text('Tasks'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(
                builder: (_) => ActivityPlayScreen(
                  contentId: item['contentId'],
                  unitId: item['unitId'],
                  lessonId: item['lessonId'],
                  activityId: item['activityId'],
                  activityTitle: item['title'],
                  collectionName: 'content',
                  isPreview: true,
                ),
              ));
            },
            style: ElevatedButton.styleFrom(backgroundColor: greenPrimary),
            icon: const Icon(Icons.play_arrow, color: Colors.white, size: 18),
            label: const Text('Preview', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _chip(IconData icon, String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3))),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 13, color: color), const SizedBox(width: 5),
      Text(label, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.bold)),
    ]),
  );

  Widget _buildContentHeader(Map<String, dynamic> item) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(top: 24, bottom: 8),
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
    decoration: BoxDecoration(
      gradient: const LinearGradient(colors: [greenPrimary, greenAccent],
          begin: Alignment.centerLeft, end: Alignment.centerRight),
      borderRadius: BorderRadius.circular(16),
      boxShadow: [BoxShadow(color: greenPrimary.withOpacity(0.35), blurRadius: 10, offset: const Offset(0, 5))],
    ),
    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Icon(Icons.book_rounded, color: Colors.white, size: 20),
      const SizedBox(width: 10),
      Text(item['title'], style: const TextStyle(color: Colors.white, fontSize: 17,
          fontWeight: FontWeight.bold, letterSpacing: 0.5)),
    ]),
  );

  Widget _buildUnitHeader(Map<String, dynamic> item) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(top: 24, bottom: 12),
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
    decoration: BoxDecoration(
      gradient: const LinearGradient(colors: [greenPrimary, greenAccent],
          begin: Alignment.centerLeft, end: Alignment.centerRight),
      borderRadius: BorderRadius.circular(16),
      boxShadow: [BoxShadow(color: greenPrimary.withOpacity(0.35), blurRadius: 10, offset: const Offset(0, 5))],
    ),
    child: Row(children: [
      const Icon(Icons.layers, color: Colors.white, size: 20), const SizedBox(width: 10),
      Text('Unit ${item['unitIndex']} · ${item['unitTitle']}',
          style: const TextStyle(color: Colors.white, fontSize: 16,
              fontWeight: FontWeight.bold, letterSpacing: 0.5)),
    ]),
  );

  Widget _buildLessonHeader(Map<String, dynamic> item) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(top: 16, bottom: 8),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    decoration: BoxDecoration(
      color: Colors.white, borderRadius: BorderRadius.circular(12),
      border: Border.all(color: greenPrimary.withOpacity(0.25)),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))],
    ),
    child: Row(children: [
      Icon(Icons.bookmark_outlined, size: 16, color: greenPrimary.withOpacity(0.7)),
      const SizedBox(width: 8),
      Text(item['lessonTitle'], style: const TextStyle(fontSize: 14,
          fontWeight: FontWeight.w600, color: Colors.black87)),
    ]),
  );

  void _showQuizDialog(Map<String, dynamic> item) {
    final bool isUnitQuiz = (item['quizType'] ?? '') == 'unit_test';
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          Icon(isUnitQuiz ? Icons.assignment_turned_in : Icons.quiz,
              color: const Color(0xFF7C3AED)),
          const SizedBox(width: 8),
          Expanded(child: Text(item['title'],
              style: const TextStyle(fontWeight: FontWeight.bold))),
        ]),
        content: Wrap(spacing: 8, runSpacing: 8, children: [
          _chip(Icons.star, '${item['xpReward']} XP${isUnitQuiz ? ' (graded)' : ' (practice)'}', Colors.amber),
          _chip(Icons.question_answer, '${item['questionCount']} questions', Colors.blue),
          _chip(isUnitQuiz ? Icons.grade : Icons.school,
              isUnitQuiz ? 'Unit Test' : 'Lesson Quiz',
              isUnitQuiz ? Colors.orange : Colors.grey),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              
              if (isUnitQuiz) {
                // ✅ Navigate to Unit Quiz Play Screen
                Navigator.push(context, MaterialPageRoute(
                  builder: (_) => UnitQuizPlayScreen(
                    contentId: item['contentId'],
                    unitId: item['unitId'],
                    quizId: item['quizId'],
                    quizTitle: item['title'],
                    isPreview: true,
                  ),
                ));
              } else {
                // Lesson quiz - use existing QuizPlayScreen
                Navigator.push(context, MaterialPageRoute(
                  builder: (_) => LessonQuizPlayScreen(
                    contentId: item['contentId'],
                    unitId: item['unitId'],
                    lessonId: item['lessonId'],
                    quizId: item['quizId'],
                    quizTitle: item['title'],
                    // collectionName: 'quizzes',
                    isPreview: true,
                  ),
                ));
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF7C3AED)),
            icon: const Icon(Icons.play_arrow, color: Colors.white, size: 18),
            label: const Text('Preview', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildQuizRow(Map<String, dynamic> item) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: GestureDetector(
      onTap: () => _showQuizDialog(item),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF3E8FF), borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF7C3AED).withOpacity(0.35)),
          boxShadow: [BoxShadow(color: const Color(0xFF7C3AED).withOpacity(0.08),
              blurRadius: 8, offset: const Offset(0, 3))],
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: const Color(0xFF7C3AED).withOpacity(0.12),
                borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.quiz, color: Color(0xFF7C3AED), size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(item['title'], style: const TextStyle(fontSize: 14,
                fontWeight: FontWeight.bold, color: Color(0xFF4B1D96))),
            const SizedBox(height: 4),
            Text('${item['questionCount']} questions · ${item['xpReward']} XP ${(item['quizType'] == 'unit_test') ? 'graded' : 'practice'}',
                style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          ])),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: Colors.amber.withOpacity(0.15),
                borderRadius: BorderRadius.circular(20)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.star, size: 13, color: Colors.amber), const SizedBox(width: 3),
              Text('${item['xpReward']} XP', style: const TextStyle(fontSize: 11,
                  fontWeight: FontWeight.bold, color: Colors.amber)),
            ]),
          ),
        ]),
      ),
    ),
  );

  Widget _buildUnitMascot(int unitIndex) {
    final path = _unitMascots[(unitIndex - 1) % _unitMascots.length];
    return Center(child: Lottie.asset(path, width: 130, height: 130));
  }

  Widget _buildActivityBubble(Map<String, dynamic> item, bool isLeft) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 20),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisAlignment: isLeft ? MainAxisAlignment.start : MainAxisAlignment.end,
      children: [
        Column(children: [
          GestureDetector(
            onTap: () => _showActivityDialog(item),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 12),
              width: 76, height: 76,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [greenPrimary, greenAccent],
                    begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: greenPrimary.withOpacity(0.35),
                    blurRadius: 12, offset: const Offset(0, 6))],
              ),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.assignment_rounded, color: Colors.white, size: 28),
                const SizedBox(height: 2),
                Text('${item['xpBase']} XP', style: const TextStyle(color: Colors.white70,
                    fontSize: 9, fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(width: 100, child: Text(item['title'],
              textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                  color: Colors.black87))),
        ]),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final body = FutureBuilder<List<Map<String, dynamic>>>(
      future: _contentFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return widget.embedded
              ? const SizedBox(height: 200,
                  child: Center(child: CircularProgressIndicator(color: greenPrimary)))
              : const Center(child: CircularProgressIndicator());
        }

        final items = snapshot.data ?? [];
        final hasActivities = items.any((i) => i['type'] == 'activity' || i['type'] == 'quiz');

        if (!hasActivities) {
          if (widget.embedded) {
            return Padding(
              padding: const EdgeInsets.all(32.0),
              child: Column(children: [
                Icon(Icons.assignment_rounded, size: 60, color: Colors.grey[300]),
                const SizedBox(height: 16),
                const Text('No Activities Yet',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text('Assign approved content to see the activity map here',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: Colors.grey[600])),
              ]),
            );
          }
          return Center(child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.assignment_rounded, size: 100, color: Colors.grey[300]),
              const SizedBox(height: 24),
              const Text('No Activities Yet',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Text('Create activities for this group and they will appear here',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, color: Colors.grey[600])),
            ]),
          ));
        }

        final Map<String, int> unitActivityCounts = {};
        final Map<String, int> unitIndexMap = {};
        for (final item in items) {
          if (item['type'] == 'unit_header') {
            unitIndexMap[item['unitId'] as String] = item['unitIndex'] as int;
            unitActivityCounts[item['unitId'] as String] = 0;
          } else if (item['type'] == 'activity') {
            final uid = item['unitId'] as String;
            unitActivityCounts[uid] = (unitActivityCounts[uid] ?? 0) + 1;
          }
        }

        int activityIndex = 0;
        final Map<String, int> unitActivityProgress = {};
        final widgets = <Widget>[];

        for (final item in items) {
          if (item['type'] == 'content_header') {
            widgets.add(_buildContentHeader(item));
          } else if (item['type'] == 'unit_header') {
            widgets.add(_buildUnitHeader(item));
          } else if (item['type'] == 'lesson_header') {
            widgets.add(_buildLessonHeader(item));
          } else if (item['type'] == 'activity') {
            final unitId = item['unitId'] as String;
            final count = unitActivityCounts[unitId] ?? 0;
            final progress = unitActivityProgress[unitId] ?? 0;
            final midPoint = count ~/ 2;
            final isLeft = activityIndex % 2 == 0;
            activityIndex++;
            widgets.add(_buildActivityBubble(item, isLeft));
            if (count > 0 && progress == midPoint) {
              widgets.add(_buildUnitMascot(unitIndexMap[unitId]!));
            }
            unitActivityProgress[unitId] = progress + 1;
          } else if (item['type'] == 'quiz') {
            widgets.add(_buildQuizRow(item));
          }
        }

        if (widget.embedded) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: SingleChildScrollView(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: widgets)),
          );
        }

        return SafeArea(child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 60),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Content', style: TextStyle(fontSize: 24,
                fontWeight: FontWeight.bold, color: greenPrimary)),
            const SizedBox(height: 8),
            ...widgets,
          ]),
        ));
      },
    );

    if (widget.embedded) {
      return Container(color: const Color(0xFFE8F5E9), child: body);
    }
    return Scaffold(backgroundColor: const Color(0xFFE8F5E9), body: body);
  }
}