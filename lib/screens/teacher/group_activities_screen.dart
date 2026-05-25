import 'package:flutter/material.dart';
import 'package:loringo_app/screens/teacher/teacher_level_screen.dart';

/// Full-screen wrapper for the group activities level map.
class GroupActivitiesScreen extends StatelessWidget {
  final String groupId;
  final String groupName;
  final Color groupColor;
  final List<Map<String, dynamic>>? preloadedItems;

  const GroupActivitiesScreen({
    super.key,
    required this.groupId,
    required this.groupName,
    required this.groupColor,
    this.preloadedItems,
  });

  @override
  Widget build(BuildContext context) {
    return TeacherLevelScreen(
      groupId: groupId,
      groupName: groupName,
      preloadedItems: preloadedItems,
    );
  }
}
