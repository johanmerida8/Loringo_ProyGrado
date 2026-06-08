import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:loringo_app/screens/teacher/student_quiz_review_screen.dart';
import 'package:loringo_app/theme/app_theme.dart';

class StudentDetailedProgressScreen extends StatefulWidget {
  final String studentId;
  final String studentName;
  final String groupId;

  const StudentDetailedProgressScreen({
    super.key,
    required this.studentId,
    required this.studentName,
    required this.groupId,
  });

  @override
  State<StudentDetailedProgressScreen> createState() => _StudentDetailedProgressScreenState();
}

class _StudentDetailedProgressScreenState extends State<StudentDetailedProgressScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text('${widget.studentName} – Progress'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Activities', icon: Icon(Icons.assignment)),
            Tab(text: 'Quizzes', icon: Icon(Icons.quiz)),
          ],
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _ActivitiesTab(studentId: widget.studentId),
          _QuizzesTab(studentId: widget.studentId, studentName: widget.studentName),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
// Activities Tab
// ──────────────────────────────────────────────────────────────────────────
class _ActivitiesTab extends StatefulWidget {
  final String studentId;

  const _ActivitiesTab({required this.studentId});

  @override
  State<_ActivitiesTab> createState() => _ActivitiesTabState();
}

class _ActivitiesTabState extends State<_ActivitiesTab> {
  final Map<String, String> _activityTitleCache = {};

  Widget _buildStars(int starCount) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) {
        if (i < starCount) {
          return const Icon(Icons.star, color: Colors.amber, size: 16);
        } else {
          return const Icon(Icons.star_border, color: Colors.amber, size: 16);
        }
      }),
    );
  }

  Future<String> _getActivityTitle(String activityId, String contentId, String unitId) async {
    final key = '$contentId|$unitId|$activityId';
    if (_activityTitleCache.containsKey(key)) {
      return _activityTitleCache[key]!;
    }
    try {
      final lessonsSnapshot = await FirebaseFirestore.instance
          .collection('content')
          .doc(contentId)
          .collection('units')
          .doc(unitId)
          .collection('lessons')
          .get();

      for (final lessonDoc in lessonsSnapshot.docs) {
        final activityDoc = await FirebaseFirestore.instance
            .collection('content')
            .doc(contentId)
            .collection('units')
            .doc(unitId)
            .collection('lessons')
            .doc(lessonDoc.id)
            .collection('activities')
            .doc(activityId)
            .get();

        if (activityDoc.exists) {
          final title = activityDoc.data()?['title'] as String?;
          if (title != null && title.isNotEmpty) {
            _activityTitleCache[key] = title;
            return title;
          }
        }
      }
      _activityTitleCache[key] = activityId;
      return activityId;
    } catch (e) {
      debugPrint('Error loading activity title for $activityId: $e');
      _activityTitleCache[key] = activityId;
      return activityId;
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('students')
          .doc(widget.studentId)
          .collection('progress')
          .where('isCompleted', isEqualTo: true)
          .where('activityId', isNotEqualTo: null)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data?.docs ?? [];
        final activityDocs = docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final hasQuizId = data.containsKey('quizId') && data['quizId'] != null && data['quizId'].toString().isNotEmpty;
          return !hasQuizId;
        }).toList();

        if (activityDocs.isEmpty) {
          return const Center(child: Text('No activities completed yet'));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: activityDocs.length,
          itemBuilder: (context, index) {
            final data = activityDocs[index].data() as Map<String, dynamic>;
            final activityId = data['activityId'] as String? ?? '';
            final contentId = data['contentId'] as String? ?? '';
            final unitId = data['unitId'] as String? ?? '';
            final bestScore = (data['bestScore'] as num?)?.toInt() ?? 0;
            final storedStars = data['stars'] as int?;
            int starCount;
            if (storedStars != null) {
              starCount = storedStars;
            } else {
              if (bestScore >= 90) starCount = 3;
              else if (bestScore >= 70) starCount = 2;
              else starCount = 1;
            }
            final completedAt = data['lastCompletedAt'] as Timestamp?;
            final dateStr = completedAt != null
                ? _formatDate(completedAt.toDate())
                : 'Unknown date';

            return FutureBuilder<String>(
              future: _getActivityTitle(activityId, contentId, unitId),
              builder: (context, titleSnapshot) {
                final title = titleSnapshot.data ?? activityId;
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: AppColors.primary.withOpacity(0.1),
                      child: Text('$bestScore%'),
                    ),
                    title: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title),
                        const SizedBox(height: 4),
                        _buildStars(starCount),
                      ],
                    ),
                    subtitle: Text('Completed: $dateStr'),
                    trailing: Text('$bestScore%',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
// Quizzes Tab
// ──────────────────────────────────────────────────────────────────────────
class _QuizzesTab extends StatefulWidget {
  final String studentId;
  final String studentName;

  const _QuizzesTab({required this.studentId, required this.studentName});

  @override
  State<_QuizzesTab> createState() => _QuizzesTabState();
}

class _QuizzesTabState extends State<_QuizzesTab> {
  final Map<String, Map<String, dynamic>> _quizCache = {};

  Future<Map<String, dynamic>> _getQuizInfo(String quizId) async {
    if (_quizCache.containsKey(quizId)) {
      return _quizCache[quizId]!;
    }
    try {
      final doc = await FirebaseFirestore.instance
          .collection('quizzes')
          .doc(quizId)
          .get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        final info = {
          'title': data['title'] as String? ?? 'Unknown Quiz',
          'type': data['type'] as String? ?? 'lesson',
        };
        _quizCache[quizId] = info;
        return info;
      } else {
        _quizCache[quizId] = {'title': 'Deleted Quiz', 'type': 'unknown'};
        return _quizCache[quizId]!;
      }
    } catch (e) {
      debugPrint('Error loading quiz info for $quizId: $e');
      _quizCache[quizId] = {'title': 'Error loading', 'type': 'unknown'};
      return _quizCache[quizId]!;
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('students')
          .doc(widget.studentId)
          .collection('progress')
          .where('isCompleted', isEqualTo: true)
          .where('quizId', isNotEqualTo: null)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        
        final docs = snapshot.data?.docs ?? [];

        final validDocs = docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final quizId = data['quizId'] as String?;
          return quizId != null && quizId.isNotEmpty;
        }).toList();

        if (validDocs.isEmpty) {
          return const Center(child: Text('No quizzes taken yet'));
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: validDocs.length,
          itemBuilder: (context, index) {
            final data = validDocs[index].data() as Map<String, dynamic>;
            final quizId = data['quizId'] as String;
            final contentId = data['contentId'] as String? ?? '';
            final unitId = data['unitId'] as String? ?? '';
            final score = data['score'] as int? ?? 0;
            final total = data['totalQuestions'] as int? ?? 0;
            final stars = data['stars'] as int? ?? 0;
            final completedAt = data['completedAt'] as Timestamp?;
            final dateStr = completedAt != null
                ? _formatDate(completedAt.toDate())
                : 'Unknown date';
            final percentage = total == 0 ? 0 : (score / total * 100).round();

            return FutureBuilder<Map<String, dynamic>>(
              future: _getQuizInfo(quizId),
              builder: (context, infoSnapshot) {
                if (infoSnapshot.connectionState == ConnectionState.waiting) {
                  return const Card(
                    child: ListTile(
                      leading: SizedBox(width: 40, height: 40, child: CircularProgressIndicator()),
                      title: Text('Loading...'),
                    ),
                  );
                }
                if (infoSnapshot.hasError || !infoSnapshot.hasData) {
                  return Card(
                    child: ListTile(
                      leading: const Icon(Icons.error, color: Colors.red),
                      title: Text('Error loading quiz'),
                      subtitle: Text(quizId),
                    ),
                  );
                }
                final info = infoSnapshot.data!;
                final isUnitQuiz = info['type'] == 'unit';
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    children: [
                      ListTile(
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.amber.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(
                            child: Text(_getStarString(stars), style: const TextStyle(fontSize: 16)),
                          ),
                        ),
                        title: Text(info['title']),
                        subtitle: Text('$score/$total correct • $dateStr'),
                        trailing: Text('$percentage%'),
                      ),
                      if (isUnitQuiz)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                          child: SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => StudentQuizReviewScreen(
                                      studentId: widget.studentId,
                                      studentName: widget.studentName,
                                      quizId: quizId,
                                      quizTitle: info['title'],
                                      unitId: unitId,
                                      contentId: contentId,
                                    ),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.visibility, size: 18),
                              label: const Text('Review Answers'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.primary,
                                side: const BorderSide(color: AppColors.primary),
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
      },
    );
  }

  String _getStarString(int stars) {
    switch (stars) {
      case 3: return '⭐⭐⭐';
      case 2: return '⭐⭐';
      case 1: return '⭐';
      default: return '☆';
    }
  }
}

String _formatDate(DateTime date) {
  return '${date.day}/${date.month}/${date.year}';
}