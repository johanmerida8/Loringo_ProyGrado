import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class StudentGroupTab extends StatefulWidget {
  final String studentId;
  final String studentName;
  final String? studentAvatar;

  const StudentGroupTab({
    super.key,
    required this.studentId,
    required this.studentName,
    this.studentAvatar,
  });

  @override
  State<StudentGroupTab> createState() => _StudentGroupTabState();
}

class _StudentGroupTabState extends State<StudentGroupTab> {
  String? groupName;

  @override
  void initState() {
    super.initState();
    _loadGroupInfo();
  }

  Future<void> _loadGroupInfo() async {
    try {
      final studentDoc = await FirebaseFirestore.instance
          .collection('students')
          .doc(widget.studentId)
          .get();

      if (studentDoc.exists) {
        final studentData = studentDoc.data();
        final groupId = studentData?['groupId'] as String?;

        if (groupId != null) {
          final groupDoc = await FirebaseFirestore.instance
              .collection('teacherGroups')
              .doc(groupId)
              .get();

          if (groupDoc.exists) {
            final groupData = groupDoc.data();
            setState(() {
              groupName = groupData?['name'] ?? 'No group assigned';
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading group info: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFE8F5E9), Colors.white],
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
        ),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 20),
                CircleAvatar(
                  radius: 60,
                  backgroundColor: const Color(0xFF4CAF50),
                  backgroundImage: widget.studentAvatar != null
                      ? AssetImage(widget.studentAvatar!) : null,
                  child: widget.studentAvatar == null
                      ? const Icon(Icons.person, size: 60, color: Colors.white) : null,
                ),
                const SizedBox(height: 24),
                Text(widget.studentName,
                    style: const TextStyle(
                        fontSize: 28, fontWeight: FontWeight.bold,
                        color: Color(0xFF4CAF50))),
                const SizedBox(height: 8),
                const Text('Student',
                    style: TextStyle(fontSize: 16, color: Colors.grey)),
                const SizedBox(height: 40),
                _buildGroupCard(),
                const SizedBox(height: 40),
                _buildMotivationCard(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGroupCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            colors: [Color(0xFF4CAF50), Color(0xFF81C784)],
            begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(
            color: const Color(0xFF4CAF50).withOpacity(0.3),
            offset: const Offset(0, 4), blurRadius: 8)],
      ),
      child: Column(
        children: [
          const Icon(Icons.groups_rounded, size: 48, color: Colors.white),
          const SizedBox(height: 16),
          const Text('My Group',
              style: TextStyle(fontSize: 18, color: Colors.white,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(groupName ?? 'Loading...',
              style: const TextStyle(fontSize: 24, color: Colors.white,
                  fontWeight: FontWeight.bold),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _buildMotivationCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(
            color: Colors.black.withOpacity(0.1),
            offset: const Offset(0, 4), blurRadius: 8)],
      ),
      child: Column(
        children: [
          const Icon(Icons.emoji_events_rounded, size: 48,
              color: Color(0xFFFE5D26)),
          const SizedBox(height: 16),
          const Text('Keep Learning!',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold,
                  color: Color(0xFFFE5D26))),
          const SizedBox(height: 8),
          Text(
            'You\'re doing great! Complete more activities to improve your skills.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: Colors.grey[700]),
          ),
        ],
      ),
    );
  }
}