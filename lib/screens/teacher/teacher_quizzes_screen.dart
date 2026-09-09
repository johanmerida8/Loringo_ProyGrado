// teacher_quizzes_screen.dart
// "Quizzes" tab — lists the teacher's active (non-archived) classroom
// groups. Tapping a group pushes GroupQuizzesScreen, which shows that
// group's Content -> Unit -> Lesson quiz structure (Summative/Formative),
// filtered by the All/Summative/Formative chips there. Quiz creation now
// happens per-row inside GroupQuizzesScreen (tap an empty slot), not via a
// standalone picker sheet -- the destination is already known from context,
// so there's nothing left for a wizard to resolve.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:loringo_app/screens/teacher/group_quizzes_screen.dart';
import 'package:loringo_app/screens/teacher/widgets/teacher_screen_header.dart';
import 'package:loringo_app/services/database/database.dart';
import 'package:loringo_app/theme/app_theme.dart';

class TeacherQuizzesScreen extends StatelessWidget {
  const TeacherQuizzesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final teacherId = FirebaseAuth.instance.currentUser?.uid;
    if (teacherId == null) {
      return const Scaffold(body: Center(child: Text('Not authenticated')));
    }
    return _Body(teacherId: teacherId);
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.teacherId});
  final String teacherId;

  static const Color _green = AppColors.primary;

  Color _groupColor(Map<String, dynamic> data) {
    final hex = data['colorHex'] as String?;
    if (hex == null) return _green;
    try {
      return Color(int.parse('FF${hex.replaceAll('#', '')}', radix: 16));
    } catch (_) {
      return _green;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBackground,
      body: Column(
        children: [
          const TeacherScreenHeader(title: 'Quizzes', color: _green),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: Database().getTeacherGroupsStream(teacherId),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return Center(child: CircularProgressIndicator(color: _green));
                }
                final groups = (snap.data?.docs ?? const <QueryDocumentSnapshot>[])
                    .where((d) => (d.data() as Map)['archived'] != true)
                    .toList()
                  ..sort((a, b) {
                    final aTime = (a.data() as Map)['createdAt'] as Timestamp?;
                    final bTime = (b.data() as Map)['createdAt'] as Timestamp?;
                    if (aTime == null && bTime == null) return 0;
                    if (aTime == null) return 1;
                    if (bTime == null) return -1;
                    return bTime.compareTo(aTime);
                  });

                if (groups.isEmpty) {
                  return const _EmptyState(
                    icon: Icons.groups_outlined,
                    title: 'No Groups Yet',
                    subtitle: 'Create a group first, then come back here to manage its quizzes.',
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(
                      AppSpacing.md, AppSpacing.sm, AppSpacing.md, 100),
                  itemCount: groups.length,
                  itemBuilder: (context, i) {
                    final doc = groups[i];
                    final data = doc.data() as Map<String, dynamic>;
                    final color = _groupColor(data);
                    final classroom = data['classroom'] as String? ?? '';
                    final year = data['academicYear']?.toString();
                    final subtitle = [if (year != null) year, if (classroom.isNotEmpty) classroom].join(' · ');
                    final name = data['name'] as String? ?? 'Group';
                    return _GroupRow(
                      order: i + 1,
                      title: name,
                      subtitle: subtitle,
                      color: color,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => GroupQuizzesScreen(
                            groupId: doc.id,
                            groupName: name,
                            groupColor: color,
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Group row ────────────────────────────────────────────────────────────

class _GroupRow extends StatelessWidget {
  const _GroupRow({
    required this.order,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final int order;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.md - 2),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppRadii.md),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 3)),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 44, height: 44,
              margin: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(AppRadii.md)),
              child: Center(
                child: Text('$order',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: color)),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md - 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                    ],
                  ],
                ),
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
            const SizedBox(width: AppSpacing.sm),
          ],
        ),
      ),
    );
  }
}

// ── Empty state ──────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.title, required this.subtitle});
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 72, color: Colors.grey[300]),
            const SizedBox(height: AppSpacing.md),
            Text(title,
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey[700])),
            const SizedBox(height: AppSpacing.sm),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.grey[500])),
          ],
        ),
      ),
    );
  }
}
