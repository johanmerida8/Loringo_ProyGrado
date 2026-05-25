import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:loringo_app/screens/teacher/quiz_management_screen.dart';
import 'package:loringo_app/services/database/database.dart';

class QuizzesTab extends StatelessWidget {
  QuizzesTab({
    super.key,
    required this.groupId,
    required this.groupColor,
    this.contentStream,
  });

  final String groupId;
  final Color groupColor;
  /// Optional override stream. When provided, the tab uses this instead of
  /// the group-filtered content stream (used by the teacher-level quizzes screen).
  final Stream<QuerySnapshot>? contentStream;
  final Database _db = Database();

  @override
  Widget build(BuildContext context) {
    final teacherId = FirebaseAuth.instance.currentUser?.uid;
    if (teacherId == null) {
      return const Center(child: Text('Error: Not authenticated'));
    }

    return StreamBuilder<QuerySnapshot>(
      stream: contentStream ?? _db.getPersonalizedContentStream(groupId),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final approvedContent = snapshot.data!.docs;
        if (approvedContent.isEmpty) {
          return const _NoApprovedContent();
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: approvedContent.length + 1,
          itemBuilder: (context, index) {
            if (index == 0) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  'Create Quizzes',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: groupColor,
                  ),
                ),
              );
            }
            final doc = approvedContent[index - 1];
            return _ContentQuizCard(
              contentDoc: doc,
              groupId: groupId,
              groupColor: groupColor,
              db: _db,
            );
          },
        );
      },
    );
  }
}

class _NoApprovedContent extends StatelessWidget {
  const _NoApprovedContent();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.quiz, size: 100, color: Colors.grey[300]),
          const SizedBox(height: 16),
          const Text(
            'No Content Available',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Text(
            'Approve content first to create quizzes',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }
}

class _ContentQuizCard extends StatelessWidget {
  const _ContentQuizCard({
    required this.contentDoc,
    required this.groupId,
    required this.groupColor,
    required this.db,
  });

  final QueryDocumentSnapshot contentDoc;
  final String groupId;
  final Color groupColor;
  final Database db;

  @override
  Widget build(BuildContext context) {
    final data = contentDoc.data() as Map<String, dynamic>;
    final title = data['title'] ?? 'Untitled';

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          _ContentHeader(title: title, color: groupColor),
          StreamBuilder<QuerySnapshot>(
            stream: db.getPersonalizedUnitsStream(groupId, contentDoc.id),
            builder: (context, unitsSnapshot) {
              if (!unitsSnapshot.hasData) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(),
                );
              }
              final units = unitsSnapshot.data!.docs;
              return Column(
                children: [
                  for (var i = 0; i < units.length; i++) ...[
                    if (i > 0) const Divider(height: 0),
                    _UnitSection(
                      groupId: groupId,
                      contentId: contentDoc.id,
                      unitDoc: units[i],
                      groupColor: groupColor,
                      db: db,
                    ),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ContentHeader extends StatelessWidget {
  const _ContentHeader({required this.title, required this.color});

  final String title;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Row(
        children: [
          Icon(Icons.folder, color: color, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UnitSection extends StatelessWidget {
  const _UnitSection({
    required this.groupId,
    required this.contentId,
    required this.unitDoc,
    required this.groupColor,
    required this.db,
  });

  final String groupId;
  final String contentId;
  final QueryDocumentSnapshot unitDoc;
  final Color groupColor;
  final Database db;

  @override
  Widget build(BuildContext context) {
    final unitData = unitDoc.data() as Map<String, dynamic>;
    final unitTitle = unitData['title'] ?? 'Untitled';

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Unit: $unitTitle',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: groupColor,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => QuizManagementScreen(
                    type: QuizManagementType.unit,
                    groupId: groupId,
                    contentId: contentId,
                    unitId: unitDoc.id,
                    title: unitTitle,
                    groupColor: groupColor,
                  ),
                ),
              ),
              icon: const Icon(Icons.assignment),
              label: const Text('Create Unit Test'),
              style: ElevatedButton.styleFrom(
                backgroundColor: groupColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          _LessonQuizList(
            groupId: groupId,
            contentId: contentId,
            unitId: unitDoc.id,
            groupColor: groupColor,
            db: db,
          ),
        ],
      ),
    );
  }
}

class _LessonQuizList extends StatelessWidget {
  const _LessonQuizList({
    required this.groupId,
    required this.contentId,
    required this.unitId,
    required this.groupColor,
    required this.db,
  });

  final String groupId;
  final String contentId;
  final String unitId;
  final Color groupColor;
  final Database db;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: db.getPersonalizedLessonsStream(groupId, contentId, unitId),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        final lessons = snapshot.data!.docs;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Lesson Quizzes',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[700],
                ),
              ),
            ),
            for (final lessonDoc in lessons)
              _LessonQuizButton(
                groupId: groupId,
                contentId: contentId,
                unitId: unitId,
                lessonDoc: lessonDoc,
                groupColor: groupColor,
              ),
          ],
        );
      },
    );
  }
}

class _LessonQuizButton extends StatelessWidget {
  const _LessonQuizButton({
    required this.groupId,
    required this.contentId,
    required this.unitId,
    required this.lessonDoc,
    required this.groupColor,
  });

  final String groupId;
  final String contentId;
  final String unitId;
  final QueryDocumentSnapshot lessonDoc;
  final Color groupColor;

  @override
  Widget build(BuildContext context) {
    final data = lessonDoc.data() as Map<String, dynamic>;
    final title = data['title'] ?? 'Untitled';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => QuizManagementScreen(
                type: QuizManagementType.lesson,
                groupId: groupId,
                contentId: contentId,
                unitId: unitId,
                lessonId: lessonDoc.id,
                title: title,
                groupColor: groupColor,
              ),
            ),
          ),
          icon: const Icon(Icons.quiz, size: 18),
          label: Text('Quiz: $title'),
          style: ElevatedButton.styleFrom(
            backgroundColor: groupColor,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ),
    );
  }
}