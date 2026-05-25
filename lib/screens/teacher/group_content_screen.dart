import 'package:flutter/material.dart';
import 'package:loringo_app/screens/teacher/create_content_screen.dart';
import 'package:loringo_app/screens/teacher/group_details/content_tab.dart';
import 'package:loringo_app/theme/app_theme.dart';

class GroupContentScreen extends StatelessWidget {
  final String groupId;
  final Color groupColor;

  const GroupContentScreen({
    super.key,
    required this.groupId,
    required this.groupColor,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        elevation: 0,
        title: const Text(
          'Content',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: ContentTab(groupId: groupId, groupColor: groupColor),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.primary,
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CreatePersonalizedContentScreen(
              groupColor: groupColor,
            ),
          ),
        ),
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}
