// lib/screens/parent/parent_home_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:loringo_app/components/notification_permission_card.dart';
import 'package:loringo_app/components/notifications_badge.dart';
import 'package:loringo_app/providers/notification_provider.dart';
import 'package:loringo_app/screens/parent/parent_profile_screen.dart';
import 'package:loringo_app/theme/app_theme.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// The "Home" tab content for the parent role — greeting banner, summary
/// cards, and the children list preview. Extracted out of
/// ParentNavigationScreen so that screen can stay a thin shell purely
/// responsible for switching between tabs (drawer on web, bottom nav on
/// mobile), with this widget owning the actual Home content and its own
/// profile shortcut.
class ParentHomeScreen extends StatelessWidget {
  final bool isWide;
  final String parentName;
  final String parentEmail;
  final String? parentUserId;
  final List<Map<String, dynamic>> myChildren;
  final Map<String, String> groupNames;
  final VoidCallback onSeeAllChildren;
  final VoidCallback onNavigateToNotifications;
  final VoidCallback onLogout;
  final VoidCallback onDeleteAccount;

  const ParentHomeScreen({
    super.key,
    required this.isWide,
    required this.parentName,
    required this.parentEmail,
    required this.parentUserId,
    required this.myChildren,
    required this.groupNames,
    required this.onSeeAllChildren,
    required this.onNavigateToNotifications,
    required this.onLogout,
    required this.onDeleteAccount,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(20, 20, 20, 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // On web the drawer's header avatar already covers this — showing
                // it again inline here would be redundant. On mobile there's no
                // visible drawer, so this inline icon is the only way to reach
                // ParentProfileScreen.
                if (!isWide)
                  GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ParentProfileScreen(
                          parentName: parentName,
                          parentEmail: parentEmail,
                          parentId: parentUserId,
                          onLogout: onLogout,
                          onDeleteAccount: onDeleteAccount,
                        ),
                      ),
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.person_rounded,
                          color: AppColors.primary, size: 24),
                    ),
                  )
                else
                  const SizedBox.shrink(),
                NotificationBadge(
                  userId: parentUserId ?? '',
                  onTap: onNavigateToNotifications,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
              decoration: BoxDecoration(
                  color: AppColors.primary, borderRadius: BorderRadius.circular(20)),
              child: Text('Hello, $parentName!',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: _summaryCard(
                    icon: Icons.people_alt_rounded,
                    label: 'Children',
                    value: '${myChildren.length}',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _summaryCard(
                    icon: Icons.groups_rounded,
                    label: 'In Groups',
                    value:
                        '${myChildren.where((c) => (c['groupId'] as String?)?.isNotEmpty == true).length}',
                  ),
                ),
              ],
            ),
          ),
          if (!kIsWeb)
            Consumer<NotificationProvider>(
              builder: (context, notificationProvider, child) {
                if (notificationProvider.isLoading) {
                  return const SizedBox.shrink();
                }
                if (!notificationProvider.isEnabled &&
                    !notificationProvider.isPermanentlyDenied) {
                  return NotificationPermissionCard(
                    onRequestPermission: () async {
                      await notificationProvider.enableNotifications(context);
                    },
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('My Children',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                TextButton.icon(
                  onPressed: onSeeAllChildren,
                  icon: const Icon(Icons.arrow_forward,
                      size: 16, color: AppColors.primary),
                  label: const Text('See all',
                      style: TextStyle(color: AppColors.primary)),
                ),
              ],
            ),
          ),
          if (myChildren.isEmpty)
            _emptyPlaceholder()
          else if (isWide)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 4,
                children: myChildren
                    .take(6)
                    .map((child) => _buildChildSummaryCard(child))
                    .toList(),
              ),
            )
          else
            ...myChildren.take(3).map((child) => Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                  child: _buildChildSummaryCard(child),
                )),
        ],
      ),
    );
  }

  Widget _buildChildSummaryCard(Map<String, dynamic> child) {
    final hasGroup = (child['groupId'] as String?)?.isNotEmpty == true;
    final avatarPath = child['avatar'] as String? ?? 'assets/avatars/panda.png';
    final childName = child['names'] as String? ?? 'Student';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: AppColors.primarySoft(0.15),
            child: ClipOval(
              child: Image.asset(
                avatarPath,
                fit: BoxFit.cover,
                width: 48,
                height: 48,
                errorBuilder: (context, error, stackTrace) {
                  return Text(
                    childName[0].toUpperCase(),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                      fontSize: 18,
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  childName,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                Text(
                  hasGroup
                      ? groupNames[child['id']] ?? 'Unknown Group'
                      : 'No group assigned',
                  style: TextStyle(
                    fontSize: 12,
                    color: hasGroup ? AppColors.primary : Colors.orange,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryCard({required IconData icon, required String label, required String value}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration:
          BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: AppColors.primary, size: 22),
          ),
          const SizedBox(height: 8),
          Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _emptyPlaceholder() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.child_care_rounded, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 10),
            Text('No children registered yet', style: TextStyle(color: Colors.grey[500])),
          ],
        ),
      ),
    );
  }
}