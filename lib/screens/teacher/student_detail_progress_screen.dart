import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:loringo_app/providers/locale_provider.dart';
import 'package:loringo_app/screens/teacher/activity_review_screen.dart';
import 'package:loringo_app/screens/teacher/lesson_quiz_review_screen.dart';
import 'package:loringo_app/screens/teacher/unit_quiz_review_screen.dart';
import 'package:loringo_app/screens/teacher/widgets/teacher_screen_header.dart';
import 'package:loringo_app/services/database/database.dart';
import 'package:loringo_app/theme/app_theme.dart';

class StudentDetailedProgressScreen extends StatefulWidget {
  final String studentId;
  final String studentName;
  final String groupId;
  // null = "All Units" — muestra todas las actividades/quizzes de todas las
  // unidades. No-null = filtra a solo esa unidad, coherente con el filtro
  // ya seleccionado en StudentProgressDashboard.
  final String? unitId;
  final String? unitTitle;

  const StudentDetailedProgressScreen({
    super.key,
    required this.studentId,
    required this.studentName,
    required this.groupId,
    this.unitId,
    this.unitTitle,
  });

  @override
  State<StudentDetailedProgressScreen> createState() =>
      _StudentDetailedProgressScreenState();
}

class _StudentDetailedProgressScreenState
    extends State<StudentDetailedProgressScreen>
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
    context.watch<LocaleProvider>();
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: Column(
        children: [
          TeacherScreenHeader(
            title: 'teacher.student_detail_progress_screen.studentProgressTitle'
                .tr(namedArgs: {'name': widget.studentName}),
            // Deja explícito qué alcance se está viendo, para que el
            // profesor no confunda "todo" con "solo esta unidad".
            subtitle: widget.unitId != null
                ? (widget.unitTitle ??
                    'teacher.student_detail_progress_screen.filteredUnit'.tr())
                : 'teacher.student_detail_progress_screen.allUnits'.tr(),
          ),
          TabBar(
            controller: _tabController,
            tabs: [
              Tab(
                  text: 'teacher.student_detail_progress_screen.activities'
                      .tr(),
                  icon: const Icon(Icons.assignment)),
              Tab(
                  text: 'teacher.student_detail_progress_screen.quizzes'.tr(),
                  icon: const Icon(Icons.quiz)),
            ],
            indicatorColor: AppColors.primary,
            labelColor: AppColors.primary,
            unselectedLabelColor: Colors.grey,
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _ActivitiesTab(
                  studentId: widget.studentId,
                  studentName: widget.studentName,
                  groupId: widget.groupId,
                  unitId: widget.unitId,
                ),
                _QuizzesTab(
                  studentId: widget.studentId,
                  studentName: widget.studentName,
                  groupId: widget.groupId,
                  unitId: widget.unitId,
                ),
              ],
            ),
          ),
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
  final String studentName;
  final String groupId;
  final String? unitId;

  const _ActivitiesTab({
    required this.studentId,
    required this.studentName,
    required this.groupId,
    required this.unitId,
  });

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

  Future<String> _getActivityTitle(
    String activityId,
    String contentId,
    String unitId,
  ) async {
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

  void _openReview(String activityId, String title) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ActivityReviewScreen(
          studentId: widget.studentId,
          studentName: widget.studentName,
          groupId: widget.groupId,
          activityId: activityId,
          activityTitle: title,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LocaleProvider>();
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('teacherGroups')
          .doc(widget.groupId)
          .collection('students')
          .doc(widget.studentId)
          .collection('progress')
          .where('isCompleted', isEqualTo: true)
          .where('type', isEqualTo: 'activity')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data?.docs ?? [];
        final activityDocs = docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;

          // Filtro por unidad en cliente (evita índice compuesto en
          // Firestore para isNotEqualTo + isEqualTo en campos distintos).
          // null = All Units, sin filtro adicional.
          if (widget.unitId != null) {
            final docUnitId = data['unitId'] as String? ?? '';
            if (docUnitId != widget.unitId) return false;
          }

          return true;
        }).toList();

        if (activityDocs.isEmpty) {
          return Center(
            child: Text(
              widget.unitId != null
                  ? 'teacher.student_detail_progress_screen.noActivitiesInUnit'
                      .tr()
                  : 'teacher.student_detail_progress_screen.noActivitiesYet'
                      .tr(),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: activityDocs.length,
          itemBuilder: (context, index) {
            final data = activityDocs[index].data() as Map<String, dynamic>;
            final activityId = activityDocs[index].id;
            final contentId = data['contentId'] as String? ?? '';
            final unitId = data['unitId'] as String? ?? '';
            final bestScore = (data['bestScore'] as num?)?.toInt() ?? 0;
            final storedStars = data['stars'] as int?;
            int starCount;
            if (storedStars != null) {
              starCount = storedStars;
            } else {
              if (bestScore >= 90)
                starCount = 3;
              else if (bestScore >= 70)
                starCount = 2;
              else
                starCount = 1;
            }
            final completedAt = data['lastCompletedAt'] as Timestamp?;
            final dateStr = completedAt != null
                ? _formatDate(completedAt.toDate())
                : 'teacher.student_detail_progress_screen.unknownDate'.tr();
            // Whether this attempt has per-task detail available for
            // review — activities completed before this feature existed
            // simply won't have a taskAnswers map, and the Review button
            // stays enabled regardless (ActivityReviewScreen shows a
            // clear "not available" message in that case rather than
            // hiding the whole entry).

            return FutureBuilder<String>(
              future: _getActivityTitle(activityId, contentId, unitId),
              builder: (context, titleSnapshot) {
                final title = titleSnapshot.data ?? activityId;
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
                    child: Column(
                      children: [
                        ListTile(
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
                          subtitle: Text(
                              'teacher.student_detail_progress_screen.completedOn'
                                  .tr(namedArgs: {'date': dateStr})),
                          trailing: Text(
                            '$bestScore%',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                          child: SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () => _openReview(activityId, title),
                              icon: const Icon(
                                Icons.rate_review_outlined,
                                size: 18,
                              ),
                              label: Text('teacher.student_detail_progress_screen.review'.tr()),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.primary,
                                side: const BorderSide(
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
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
  final String groupId;
  final String? unitId;

  const _QuizzesTab({
    required this.studentId,
    required this.studentName,
    required this.groupId,
    required this.unitId,
  });

  @override
  State<_QuizzesTab> createState() => _QuizzesTabState();
}

class _QuizzesTabState extends State<_QuizzesTab> {
  final Map<String, Map<String, dynamic>> _quizCache = {};

  /// Resolves a quiz doc from its progress doc's contentId/unitId/lessonId.
  /// [lessonId] comes straight off the progress doc when present (every
  /// quiz completed after this migration carries it). For a LEGACY progress
  /// doc saved before this migration (lessonId absent, quiz could be either
  /// scope), falls back to trying the unit-quiz path first, then scanning
  /// the unit's lessons for a matching quiz doc -- then self-heals by
  /// writing the discovered lessonId back onto that progress doc so this
  /// scan never has to run again for it.
  Future<Map<String, dynamic>> _getQuizInfo(
    String quizId,
    String contentId,
    String unitId,
    String? lessonId,
  ) async {
    if (_quizCache.containsKey(quizId)) {
      return _quizCache[quizId]!;
    }
    try {
      final db = Database();
      String? resolvedLessonId = lessonId;
      DocumentSnapshot doc;
      if (lessonId != null) {
        doc = await db.getQuiz(contentId, unitId, quizId, lessonId: lessonId);
      } else {
        doc = await db.getQuiz(contentId, unitId, quizId);
        if (!doc.exists) {
          final lessonsSnap = await db
              .personalizedLessons(contentId, unitId)
              .get();
          for (final lessonDoc in lessonsSnap.docs) {
            final candidate = await db.getQuiz(
              contentId,
              unitId,
              quizId,
              lessonId: lessonDoc.id,
            );
            if (candidate.exists) {
              doc = candidate;
              resolvedLessonId = lessonDoc.id;
              await FirebaseFirestore.instance
                  .collection('teacherGroups')
                  .doc(widget.groupId)
                  .collection('students')
                  .doc(widget.studentId)
                  .collection('progress')
                  .doc(quizId)
                  .update({'lessonId': lessonDoc.id});
              break;
            }
          }
        }
      }
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        final info = {
          'title': data['title'] as String? ??
              'teacher.student_detail_progress_screen.unknownQuiz'.tr(),
          'scope': resolvedLessonId != null ? 'lesson' : 'unit',
          'lessonId': resolvedLessonId,
        };
        _quizCache[quizId] = info;
        return info;
      } else {
        _quizCache[quizId] = {
          'title': 'teacher.student_detail_progress_screen.deletedQuiz'.tr(),
          'scope': 'unknown',
          'lessonId': null,
        };
        return _quizCache[quizId]!;
      }
    } catch (e) {
      debugPrint('Error loading quiz info for $quizId: $e');
      _quizCache[quizId] = {
        'title': 'teacher.student_detail_progress_screen.errorLoadingQuiz'.tr(),
        'scope': 'unknown',
        'lessonId': null,
      };
      return _quizCache[quizId]!;
    }
  }

  void _openReview(
    String quizId,
    String quizTitle,
    bool isUnitQuiz,
    String contentId,
    String unitId,
    String? lessonId,
  ) {
    if (isUnitQuiz) {
      // Unit Quiz keeps its existing review + parent-report flow,
      // unchanged — this screen only adds the Lesson Quiz branch below.
      // contentId/unitId come from THIS quiz's own progress doc (already
      // extracted in itemBuilder below), not from widget.unitId — the
      // latter is null whenever the teacher is viewing "All Units", but
      // UnitQuizReviewScreen needs the real, non-empty values to load
      // and later save the parent report against reports/{unitId}.
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => UnitQuizReviewScreen(
            studentId: widget.studentId,
            studentName: widget.studentName,
            groupId: widget.groupId,
            quizId: quizId,
            quizTitle: quizTitle,
            unitId: unitId,
            contentId: contentId,
          ),
        ),
      );
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => LessonQuizReviewScreen(
            studentId: widget.studentId,
            studentName: widget.studentName,
            groupId: widget.groupId,
            contentId: contentId,
            unitId: unitId,
            lessonId: lessonId!,
            quizId: quizId,
            quizTitle: quizTitle,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LocaleProvider>();
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('teacherGroups')
          .doc(widget.groupId)
          .collection('students')
          .doc(widget.studentId)
          .collection('progress')
          .where('isCompleted', isEqualTo: true)
          .where('type', isEqualTo: 'quiz')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data?.docs ?? [];

        final validDocs = docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;

          // Mismo filtro en cliente por consistencia con el tab de
          // Activities y para evitar índices compuestos.
          if (widget.unitId != null) {
            final docUnitId = data['unitId'] as String? ?? '';
            if (docUnitId != widget.unitId) return false;
          }

          return true;
        }).toList();

        if (validDocs.isEmpty) {
          return Center(
            child: Text(
              widget.unitId != null
                  ? 'teacher.student_detail_progress_screen.noQuizzesInUnit'
                      .tr()
                  : 'teacher.student_detail_progress_screen.noQuizzesYet'
                      .tr(),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: validDocs.length,
          itemBuilder: (context, index) {
            final data = validDocs[index].data() as Map<String, dynamic>;
            final quizId = validDocs[index].id;
            final contentId = data['contentId'] as String? ?? '';
            final unitId = data['unitId'] as String? ?? '';
            final progressLessonId = data['lessonId'] as String?;
            final score = data['correctAnswers'] as int? ?? 0;
            final total = data['totalQuestions'] as int? ?? 0;
            final stars = data['stars'] as int? ?? 0;
            final completedAt = data['lastCompletedAt'] as Timestamp?;
            final dateStr = completedAt != null
                ? _formatDate(completedAt.toDate())
                : 'teacher.student_detail_progress_screen.unknownDate'.tr();
            final percentage = total == 0 ? 0 : (score / total * 100).round();

            return FutureBuilder<Map<String, dynamic>>(
              future: _getQuizInfo(quizId, contentId, unitId, progressLessonId),
              builder: (context, infoSnapshot) {
                if (infoSnapshot.connectionState == ConnectionState.waiting) {
                  return Card(
                    child: ListTile(
                      leading: const SizedBox(
                        width: 40,
                        height: 40,
                        child: CircularProgressIndicator(),
                      ),
                      title: Text('teacher.student_detail_progress_screen.loading'.tr()),
                    ),
                  );
                }
                if (infoSnapshot.hasError || !infoSnapshot.hasData) {
                  return Card(
                    child: ListTile(
                      leading: const Icon(Icons.error, color: Colors.red),
                      title: Text('teacher.student_detail_progress_screen.errorLoadingQuiz'.tr()),
                      subtitle: Text(quizId),
                    ),
                  );
                }
                final info = infoSnapshot.data!;
                final isUnitQuiz = info['scope'] == 'unit';
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
                            child: Text(
                              _getStarString(stars),
                              style: const TextStyle(fontSize: 16),
                            ),
                          ),
                        ),
                        title: Text(info['title']),
                        subtitle: Text(
                            'teacher.student_detail_progress_screen.scoreCorrectDate'
                                .tr(namedArgs: {
                          'score': '$score',
                          'total': '$total',
                          'date': dateStr,
                        })),
                        trailing: Text('$percentage%'),
                      ),
                      // ── Review button ──────────────────────────────
                      // Now shown for BOTH scopes, not just Unit Quiz —
                      // previously this whole block only rendered when
                      // isUnitQuiz was true, leaving Lesson Quiz with no
                      // way to inspect answers. _openReview branches on
                      // isUnitQuiz to route to the correct screen (see
                      // above), since Unit Quiz keeps its own
                      // report-generation flow and Lesson Quiz only gets
                      // an internal feedback note.
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () => _openReview(
                              quizId,
                              info['title'],
                              isUnitQuiz,
                              contentId,
                              unitId,
                              info['lessonId'] as String?,
                            ),
                            icon: const Icon(Icons.visibility, size: 18),
                            label: Text('teacher.student_detail_progress_screen.reviewAnswers'.tr()),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: isUnitQuiz
                                  ? AppColors.primary
                                  : AppColors.info,
                              side: BorderSide(
                                color: isUnitQuiz
                                    ? AppColors.primary
                                    : AppColors.info,
                              ),
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
      case 3:
        return '⭐⭐⭐';
      case 2:
        return '⭐⭐';
      case 1:
        return '⭐';
      default:
        return '☆';
    }
  }
}

String _formatDate(DateTime date) {
  return '${date.day}/${date.month}/${date.year}';
}
