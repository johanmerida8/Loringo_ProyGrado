// quizzes_tab.dart
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
  });

  final String groupId;
  final Color groupColor;
  final Database _db = Database();

  @override
  Widget build(BuildContext context) {
    final teacherId = FirebaseAuth.instance.currentUser?.uid;
    if (teacherId == null) {
      return const Center(child: Text('Error: Not authenticated'));
    }

    return StreamBuilder<QuerySnapshot>(
      stream: _db.getTeacherContentStream(teacherId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final contentDocs = snapshot.data?.docs ?? [];
        if (contentDocs.isEmpty) {
          return const _NoContentEmptyState();
        }

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
          itemCount: contentDocs.length + 1,
          itemBuilder: (context, index) {
            if (index == 0) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Quizzes',
                      style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: groupColor),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Manage lesson quizzes and unit tests for your content',
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                    ),
                  ],
                ),
              );
            }
            final doc = contentDocs[index - 1];
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

// ── Empty state ───────────────────────────────────────────────────────────────

class _NoContentEmptyState extends StatelessWidget {
  const _NoContentEmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(color: Colors.grey.shade100, shape: BoxShape.circle),
              child: Icon(Icons.quiz_outlined, size: 56, color: Colors.grey.shade400),
            ),
            const SizedBox(height: 24),
            const Text('No Content Available', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Text(
              'Create content first to start creating quizzes for your students.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey.shade500, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Content card ──────────────────────────────────────────────────────────────

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
    final title = data['title'] as String? ?? 'Untitled';

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: groupColor.withOpacity(0.12), width: 1.5),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 12, offset: const Offset(0, 3))],
      ),
      child: Column(
        children: [
          // ── Content header ─────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: BoxDecoration(
              color: groupColor.withOpacity(0.07),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(17)),
              border: Border(bottom: BorderSide(color: groupColor.withOpacity(0.1))),
            ),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: groupColor.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
                child: Icon(Icons.folder_outlined, color: groupColor, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ]),
          ),

          // ── Units ──────────────────────────────────────────────────────
          StreamBuilder<QuerySnapshot>(
            stream: db.getPersonalizedUnitsStream(groupId, contentDoc.id),
            builder: (context, unitsSnapshot) {
              if (!unitsSnapshot.hasData) {
                return const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()));
              }
              final units = unitsSnapshot.data!.docs;
              if (units.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text('No units found', style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
                );
              }
              return Column(
                children: List.generate(units.length, (i) => _UnitSection(
                  groupId: groupId,
                  contentId: contentDoc.id,
                  unitDoc: units[i],
                  groupColor: groupColor,
                  db: db,
                  isLast: i == units.length - 1,
                )),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ── Unit section ──────────────────────────────────────────────────────────────

class _UnitSection extends StatelessWidget {
  const _UnitSection({
    required this.groupId,
    required this.contentId,
    required this.unitDoc,
    required this.groupColor,
    required this.db,
    required this.isLast,
  });

  final String groupId;
  final String contentId;
  final QueryDocumentSnapshot unitDoc;
  final Color groupColor;
  final Database db;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final unitData = unitDoc.data() as Map<String, dynamic>;
    final unitTitle = unitData['title'] as String? ?? 'Untitled';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Unit label
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
          child: Row(children: [
            Container(
              width: 4, height: 18,
              decoration: BoxDecoration(color: groupColor, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                unitTitle,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey.shade800),
              ),
            ),
          ]),
        ),

        // Unit Test button
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: _QuizActionTile(
            icon: Icons.assignment_outlined,
            label: 'Unit Test',
            subtitle: 'Graded multiple-choice exam',
            badgeLabel: 'GRADED',
            badgeColor: Colors.red.shade700,
            color: groupColor,
            onTap: () => Navigator.push(
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
          ),
        ),

        // Lesson quizzes
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Row(children: [
            Icon(Icons.quiz_outlined, size: 14, color: Colors.grey.shade500),
            const SizedBox(width: 6),
            Text('Lesson Quizzes', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade500)),
          ]),
        ),

        _LessonQuizList(
          groupId: groupId,
          contentId: contentId,
          unitId: unitDoc.id,
          groupColor: groupColor,
          db: db,
        ),

        if (!isLast)
          Divider(height: 0, thickness: 1, color: Colors.grey.shade100, indent: 16, endIndent: 16),
      ],
    );
  }
}

// ── Action tile (used for Unit Test) ─────────────────────────────────────────

class _QuizActionTile extends StatelessWidget {
  const _QuizActionTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.badgeLabel,
    required this.badgeColor,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final String badgeLabel;
  final Color badgeColor;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.2)),
          ),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(9)),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: badgeColor.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                    child: Text(badgeLabel, style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: badgeColor)),
                  ),
                ]),
                const SizedBox(height: 2),
                Text(subtitle, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
              ]),
            ),
            Icon(Icons.chevron_right_rounded, color: color.withOpacity(0.5), size: 22),
          ]),
        ),
      ),
    );
  }
}

// ── Lesson quiz list ──────────────────────────────────────────────────────────

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
        if (lessons.isEmpty) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Text('No lessons in this unit', style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
          );
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Column(
            children: lessons.map((lessonDoc) => _LessonQuizTile(
              groupId: groupId,
              contentId: contentId,
              unitId: unitId,
              lessonDoc: lessonDoc,
              groupColor: groupColor,
            )).toList(),
          ),
        );
      },
    );
  }
}

// ── Lesson quiz tile ──────────────────────────────────────────────────────────

class _LessonQuizTile extends StatelessWidget {
  const _LessonQuizTile({
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
    final title = data['title'] as String? ?? 'Untitled';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => Navigator.push(
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
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: Colors.blue.withOpacity(0.08), borderRadius: BorderRadius.circular(7)),
                child: Icon(Icons.quiz_outlined, color: Colors.blue.shade600, size: 16),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 1),
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(color: Colors.blue.withOpacity(0.08), borderRadius: BorderRadius.circular(4)),
                      child: Text('PRACTICE', style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.blue.shade700)),
                    ),
                    const SizedBox(width: 4),
                    Text('Lesson quiz', style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                  ]),
                ]),
              ),
              Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400, size: 18),
            ]),
          ),
        ),
      ),
    );
  }
}