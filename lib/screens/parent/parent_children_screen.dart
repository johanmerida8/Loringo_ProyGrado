// parent_children_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:loringo_app/screens/parent/parent_join_group_screen.dart';
import 'package:loringo_app/screens/parent/parent_register_child_screen.dart';
import 'package:loringo_app/theme/app_theme.dart';

class ParentChildrenScreen extends StatelessWidget {
  final List<Map<String, dynamic>> myChildren;
  final Map<String, String> groupNames;
  final VoidCallback onRefresh;

  const ParentChildrenScreen({
    super.key,
    required this.myChildren,
    required this.groupNames,
    required this.onRefresh,
  });

  void _showAccessCodeDialog(
      BuildContext context, Map<String, dynamic> child) {
    final accessCode = child['accessCode'] as String?;
    if (accessCode == null || accessCode.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Access code not available'),
        backgroundColor: Colors.red,
      ));
      return;
    }
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primarySoft(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.key_rounded,
                  color: AppColors.primary, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text("${child['names']}'s Code",
                  style: const TextStyle(fontSize: 18)),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Share this code with your child to log in:',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(
                  vertical: 16, horizontal: 24),
              decoration: BoxDecoration(
                color: AppColors.primarySoft(0.08),
                borderRadius: BorderRadius.circular(12),
                border:
                    Border.all(color: AppColors.primary, width: 2),
              ),
              child: Text(
                accessCode,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 6,
                  color: AppColors.primary,
                ),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: accessCode));
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                  content: Text('Code copied'),
                  backgroundColor: Colors.green,
                  duration: Duration(seconds: 2),
                ));
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.copy_rounded),
              label: const Text('Copy Code'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _navigateToJoinGroup(
      BuildContext context, Map<String, dynamic> child) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
          builder: (context) =>
              ParentJoinGroupScreen(child: child)),
    );
    if (result == true) onRefresh();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Inline header ──
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 56, 20, 4),
            child: const Text(
              'My Children',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ── Add child button ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () async {
                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) =>
                            const ParentRegisterChildScreen()),
                  );
                  if (result == true) onRefresh();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                icon: const Icon(Icons.add),
                label: const Text('Add Child',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ),

          const SizedBox(height: 20),

          if (myChildren.isEmpty)
            _emptyPlaceholder()
          else
            ...myChildren.map(
              (child) => Padding(
                padding:
                    const EdgeInsets.fromLTRB(20, 0, 20, 14),
                child: _buildChildCard(context, child),
              ),
            ),

          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildChildCard(
      BuildContext context, Map<String, dynamic> child) {
    final hasGroup =
        (child['groupId'] as String?)?.isNotEmpty == true;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _childAvatar(child, radius: 28),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        child['names'] ?? 'No name',
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: hasGroup
                                  ? AppColors.primary
                                  : Colors.orange,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            hasGroup
                                ? groupNames[child['id']] ??
                                    'Loading...'
                                : 'No group assigned',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: hasGroup
                                  ? AppColors.primary
                                  : Colors.orange,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Divider(height: 1, color: Color(0xFFF0F0F0)),
            const SizedBox(height: 12),

            // ── Action buttons row ──
            Row(
              children: [
                if (!hasGroup) ...[
                  Expanded(
                    child: _actionButton(
                      icon: Icons.add_circle_outline,
                      label: 'Join Group',
                      isPrimary: true,
                      onPressed: () =>
                          _navigateToJoinGroup(context, child),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: _actionButton(
                    icon: Icons.key_rounded,
                    label: 'Access Code',
                    isPrimary: false,
                    onPressed: () =>
                        _showAccessCodeDialog(context, child),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required bool isPrimary,
    required VoidCallback onPressed,
  }) {
    if (isPrimary) {
      return ElevatedButton.icon(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 10),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
          elevation: 0,
        ),
        icon: Icon(icon, size: 16),
        label: Text(label,
            style: const TextStyle(
                fontWeight: FontWeight.bold, fontSize: 13)),
      );
    }
    return OutlinedButton.icon(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primary,
        side: BorderSide(
            color: AppColors.primary.withOpacity(0.4), width: 1.5),
        padding: const EdgeInsets.symmetric(vertical: 10),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10)),
      ),
      icon: Icon(icon, size: 16),
      label: Text(label,
          style: const TextStyle(
              fontWeight: FontWeight.w600, fontSize: 13)),
    );
  }

  Widget _childAvatar(Map<String, dynamic> child,
      {required double radius}) {
    final avatar = child['avatar'] as String?;
    if (avatar != null && avatar.isNotEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundImage: AssetImage(avatar),
        backgroundColor: AppColors.primarySoft(0.15),
      );
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.primarySoft(0.15),
      child: Text(
        (child['names'] as String? ?? 'S')[0].toUpperCase(),
        style: TextStyle(
            fontSize: radius * 0.8,
            fontWeight: FontWeight.bold,
            color: AppColors.primary),
      ),
    );
  }

  Widget _emptyPlaceholder() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Column(
          children: [
            Icon(Icons.child_care_rounded,
                size: 72, color: Colors.grey[300]),
            const SizedBox(height: 12),
            Text('No children registered yet',
                style: TextStyle(
                    fontSize: 15, color: Colors.grey[500])),
          ],
        ),
      ),
    );
  }
}