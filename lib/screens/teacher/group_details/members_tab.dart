import 'package:flutter/material.dart';

class MembersTab extends StatelessWidget {
  const MembersTab({
    super.key,
    required this.groupColor,
    required this.isLoading,
    required this.teacherData,
    required this.students,
    required this.onInvite,
    required this.onRemoveStudent,
  });

  final Color groupColor;
  final bool isLoading;
  final Map<String, dynamic>? teacherData;
  final List<Map<String, dynamic>> students;
  final VoidCallback onInvite;
  final void Function(String studentId, String studentName) onRemoveStudent;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(text: 'Teacher', color: groupColor),
          const SizedBox(height: 12),
          _TeacherCard(groupColor: groupColor, teacherData: teacherData),
          const SizedBox(height: 32),
          _StudentsHeader(
            count: students.length,
            color: groupColor,
            onInvite: onInvite,
          ),
          const SizedBox(height: 12),
          if (students.isEmpty)
            const _StudentsEmptyState()
          else
            ...students.map(
              (s) => _StudentTile(
                student: s,
                groupColor: groupColor,
                onRemove: () =>
                    onRemoveStudent(s['id'] as String, s['name'] as String),
              ),
            ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.bold,
        color: color,
      ),
    );
  }
}

class _TeacherCard extends StatelessWidget {
  const _TeacherCard({required this.groupColor, required this.teacherData});

  final Color groupColor;
  final Map<String, dynamic>? teacherData;

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      elevation: 2,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: [
              groupColor.withOpacity(0.1),
              groupColor.withOpacity(0.05),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.all(16),
          leading: CircleAvatar(
            backgroundColor: groupColor,
            radius: 28,
            child: const Icon(Icons.school, color: Colors.white, size: 28),
          ),
          title: Text(
            teacherData?['name'] ?? 'Teacher',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                teacherData?['email'] ?? '',
                style: const TextStyle(fontSize: 14, color: Colors.black54),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: groupColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Group Owner',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
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

class _StudentsHeader extends StatelessWidget {
  const _StudentsHeader({
    required this.count,
    required this.color,
    required this.onInvite,
  });

  final int count;
  final Color color;
  final VoidCallback onInvite;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'Students ($count)',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        IconButton(
          onPressed: onInvite,
          icon: const Icon(Icons.person_add_rounded),
          color: color,
          iconSize: 28,
        ),
      ],
    );
  }
}

class _StudentsEmptyState extends StatelessWidget {
  const _StudentsEmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          children: [
            Icon(
              Icons.people_outline_rounded,
              size: 80,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'No students yet',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap + to invite students',
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
            ),
          ],
        ),
      ),
    );
  }
}

class _StudentTile extends StatelessWidget {
  const _StudentTile({
    required this.student,
    required this.groupColor,
    required this.onRemove,
  });

  final Map<String, dynamic> student;
  final Color groupColor;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final name = student['name'] as String;
    final parentEmail = student['parentEmail'] as String;
    final avatar = student['avatar'] as String;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      elevation: 2,
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: CircleAvatar(
          backgroundColor: groupColor.withOpacity(0.2),
          radius: 28,
          backgroundImage: avatar.isNotEmpty ? AssetImage(avatar) : null,
          child: avatar.isEmpty
              ? Text(
                  name.isNotEmpty ? name[0].toUpperCase() : 'E',
                  style: TextStyle(
                    color: groupColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                  ),
                )
              : null,
        ),
        title: Text(
          name,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          parentEmail.isNotEmpty ? 'Parent: $parentEmail' : 'No parent email',
          style: const TextStyle(fontSize: 14, color: Colors.black54),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
          onPressed: onRemove,
        ),
      ),
    );
  }
}
