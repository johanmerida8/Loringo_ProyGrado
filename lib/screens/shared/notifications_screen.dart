// notifications_screen.dart
//
// Role-agnostic: reads the `notifications` collection filtered by
// `userId` == the signed-in user, whatever their role. Both teachers and
// parents write into that same collection (see
// functions/src/notifyOverdueActivities.ts, which sends to both a
// teacherId and a parentId under the same schema), so this single screen
// serves both — it used to live under screens/parent/ as
// ParentNotificationsScreen and get imported directly from
// teacher_home_screen.dart, which was misleading since nothing here is
// parent-specific. The one branch that is parent-shaped (group-invitation
// handling in _handleGroupInvitation) is simply a no-op for a teacher
// account, since teachers never receive a `group_invitation` notification
// (see functions/src/groupInvitationNotifications.ts — always sent to a
// parentId).
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:loringo_app/components/app_loading_indicator.dart';
import 'package:loringo_app/providers/locale_provider.dart';
import 'package:loringo_app/services/database/database.dart';
import 'package:loringo_app/theme/app_theme.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<Map<String, dynamic>> notifications = [];
  bool isLoading = true;
  String? currentUserId;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    setState(() => isLoading = true);

    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        throw Exception('User not authenticated');
      }

      currentUserId = currentUser.uid;

      final notificationsSnapshot = await FirebaseFirestore.instance
          .collection('notifications')
          .where('userId', isEqualTo: currentUserId)
          .orderBy('createdAt', descending: true)
          .get();

      final notifs = notificationsSnapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();

      setState(() {
        notifications = notifs;
        isLoading = false;
      });
    } catch (e) {
      setState(() => isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('components.notifications_screen.errorLoading'
                .tr(namedArgs: {'error': '$e'})),
            backgroundColor: AppColors.danger,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
          ),
        );
      }
    }
  }

  Future<void> _markAsRead(String notificationId) async {
    await FirebaseFirestore.instance
        .collection('notifications')
        .doc(notificationId)
        .update({'isRead': true});
  }

  Future<void> _markAllAsRead() async {
    if (currentUserId == null) return;

    final batch = FirebaseFirestore.instance.batch();
    final unreadNotifs = notifications.where((n) => n['isRead'] == false);

    for (var notif in unreadNotifs) {
      final docRef = FirebaseFirestore.instance
          .collection('notifications')
          .doc(notif['id']);
      batch.update(docRef, {'isRead': true});
    }

    await batch.commit();
    _loadNotifications();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('components.notifications_screen.allMarkedRead'.tr()),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.md),
          ),
        ),
      );
    }
  }

  Future<void> _handleGroupInvitation(Map<String, dynamic> notification) async {
    final data = notification['data'];
    if (data == null) return;

    final groupCode = data['groupCode'] as String?;
    final groupName = data['groupName'] as String?;

    if (groupCode == null) return;

    await _markAsRead(notification['id']);

    if (!mounted) return;

    final studentsSnapshot = await FirebaseFirestore.instance
        .collection('students')
        .where('parentId', isEqualTo: currentUserId)
        .get();

    final students = studentsSnapshot.docs.map((doc) {
      final data = doc.data();
      data['id'] = doc.id;
      return data;
    }).toList();

    if (students.isEmpty) {
      _showSnackBar(
          'components.notifications_screen.noChildrenRegistered'.tr(),
          AppColors.danger);
      return;
    }

    // Every child is a valid candidate here, not just ungrouped ones —
    // accepting this invitation is allowed to switch a child already in a
    // different group, same as manually entering a group code in
    // parent_join_group_screen.dart does. The old `groupId == null` filter
    // blocked that entirely, permanently showing "all children already in
    // a group" for any parent whose kid already had one, with no way to
    // accept a new group's invitation at all.
    final availableStudents = students;

    final selectedStudentId = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.lg),
        ),
        title: Row(
          children: [
            Icon(Icons.group_add_rounded, color: AppColors.primary, size: 24),
            const SizedBox(width: AppSpacing.sm),
            Text('components.notifications_screen.joinGroupTitle'.tr()),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'components.notifications_screen.joinGroupPrompt'
                  .tr(namedArgs: {'group': '$groupName'}),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: AppSpacing.md),
            Text('components.notifications_screen.selectAChild'.tr()),
            const SizedBox(height: AppSpacing.md),
            ...availableStudents.map((student) => ListTile(
              leading: CircleAvatar(
                backgroundColor: AppColors.primary.withOpacity(0.1),
                child: Text(
                  (student['names'] as String? ?? 'C')[0].toUpperCase(),
                  style: TextStyle(color: AppColors.primary),
                ),
              ),
              title: Text(student['names'] ?? 'common.noName'.tr()),
              onTap: () => Navigator.pop(context, student['id']),
            )),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('common.cancel'.tr()),
          ),
        ],
      ),
    );

    if (selectedStudentId == null) return;

    try {
      // Hashed/verified server-side — see functions/src/groupCode.ts.
      final group = await Database().findGroupByCode(groupCode);

      if (group == null) {
        throw Exception('components.notifications_screen.groupNotFound'.tr());
      }
      if (group['archived'] == true) {
        throw Exception(
            'parent.parent_join_group_screen.groupNotAccepting'.tr());
      }
      final groupId = group['groupId'] as String;
      final student = availableStudents.firstWhere(
        (s) => s['id'] == selectedStudentId,
      );

      // Same "leaving a group" handling parent_join_group_screen.dart's
      // manual-code-entry flow already does — marks the old membership as
      // left (its XP/progress/reports stay in place, untouched) and starts
      // the student fresh under the new group — so accepting an invitation
      // switches groups exactly as cleanly as typing the code in manually
      // does.
      final previousGroupId = student['groupId'] as String?;
      await Database().switchGroup(
        studentId: selectedStudentId,
        oldGroupId: (previousGroupId != null && previousGroupId.isNotEmpty)
            ? previousGroupId
            : null,
        newGroupId: groupId,
      );

      if (mounted) {
        _showSnackBar(
            'components.notifications_screen.joinedGroupSuccess'.tr(
                namedArgs: {
                  'name': '${student['names']}',
                  'group': '$groupName',
                }),
            AppColors.success);
        _loadNotifications();
      }
    } catch (e) {
      _showSnackBar(
          'common.errorWithMessage'.tr(namedArgs: {'error': '$e'}),
          AppColors.danger);
    }
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
      ),
    );
  }

  String _formatTimeAgo(Timestamp? timestamp) {
    if (timestamp == null) return '';
    final date = timestamp.toDate();
    final difference = DateTime.now().difference(date);

    if (difference.inDays > 0) {
      return 'components.notifications_screen.daysAgo'
          .tr(namedArgs: {'count': '${difference.inDays}'});
    }
    if (difference.inHours > 0) {
      return 'components.notifications_screen.hoursAgo'
          .tr(namedArgs: {'count': '${difference.inHours}'});
    }
    if (difference.inMinutes > 0) {
      return 'components.notifications_screen.minutesAgo'
          .tr(namedArgs: {'count': '${difference.inMinutes}'});
    }
    return 'components.notifications_screen.justNow'.tr();
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LocaleProvider>();
    return Scaffold(
      backgroundColor: AppColors.scaffoldBackground,
      body: SafeArea(
        child: Column(
          children: [
            // Custom Header with Back Button
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.md,
              ),
              child: Row(
                children: [
                  // Back button
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => Navigator.pop(context, true),
                      borderRadius: BorderRadius.circular(AppRadii.md),
                      child: Container(
                        padding: const EdgeInsets.all(AppSpacing.sm),
                        decoration: BoxDecoration(
                          color: AppColors.primarySoft(0.1),
                          borderRadius: BorderRadius.circular(AppRadii.md),
                          boxShadow: AppShadows.card,
                        ),
                        child: const Icon(
                          Icons.arrow_back_rounded,
                          color: AppColors.primary,
                          size: 22,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  // Title
                  Expanded(
                    child: Text(
                      'components.notifications_screen.title'.tr(),
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                  // Mark all button (if there are unread notifications)
                  if (notifications.any((n) => n['isRead'] == false))
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: _markAllAsRead,
                        borderRadius: BorderRadius.circular(AppRadii.md),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                            vertical: AppSpacing.sm,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(AppRadii.md),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.done_all_rounded,
                                color: AppColors.primary,
                                size: 18,
                              ),
                              const SizedBox(width: AppSpacing.xs),
                              Text(
                                'components.notifications_screen.markAll'.tr(),
                                style: const TextStyle(
                                  color: AppColors.primary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // Content
            Expanded(
              child: isLoading
                  ? const AppLoadingIndicator()
                  : notifications.isEmpty
                      ? _buildEmptyState()
                      : RefreshIndicator(
                          onRefresh: _loadNotifications,
                          color: AppColors.primary,
                          child: ListView.builder(
                            padding: const EdgeInsets.all(AppSpacing.md),
                            itemCount: notifications.length,
                            itemBuilder: (context, index) {
                              final notification = notifications[index];
                              final isUnread = notification['isRead'] == false;
                              final type = notification['type'] ?? 'general';
                              final isInvitation = type == 'group_invitation';

                              return GestureDetector(
                                onTap: () {
                                  if (isInvitation) {
                                    _handleGroupInvitation(notification);
                                  } else if (isUnread) {
                                    _markAsRead(notification['id']);
                                    setState(() {
                                      notification['isRead'] = true;
                                    });
                                  }
                                },
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: AppSpacing.md),
                                  padding: const EdgeInsets.all(AppSpacing.md),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(AppRadii.lg),
                                    border: isUnread
                                        ? Border.all(color: AppColors.primary, width: 2)
                                        : null,
                                    boxShadow: AppShadows.card,
                                  ),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // Icon Container
                                      Container(
                                        width: 48,
                                        height: 48,
                                        decoration: BoxDecoration(
                                          color: isUnread
                                              ? AppColors.primary.withOpacity(0.1)
                                              : AppColors.subtleFill,
                                          borderRadius: BorderRadius.circular(AppRadii.md),
                                        ),
                                        child: Icon(
                                          isInvitation
                                              ? Icons.group_add_rounded
                                              : type == 'quiz_report'
                                                  ? Icons.quiz_rounded
                                                  : Icons.notifications_rounded,
                                          color: isUnread ? AppColors.primary : AppColors.textSecondary,
                                          size: 24,
                                        ),
                                      ),
                                      const SizedBox(width: AppSpacing.md),
                                      // Content
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              notification['title'] ??
                                                  'components.notifications_screen.notificationFallbackTitle'
                                                      .tr(),
                                              style: TextStyle(
                                                fontSize: 15,
                                                fontWeight: isUnread
                                                    ? FontWeight.bold
                                                    : FontWeight.w500,
                                                color: isUnread
                                                    ? AppColors.textPrimary
                                                    : AppColors.textSecondary,
                                              ),
                                            ),
                                            const SizedBox(height: AppSpacing.xs),
                                            Text(
                                              notification['message'] ?? '',
                                              style: TextStyle(
                                                fontSize: 13,
                                                color: AppColors.textSecondary,
                                                height: 1.4,
                                              ),
                                            ),
                                            const SizedBox(height: AppSpacing.sm),
                                            Row(
                                              children: [
                                                Icon(
                                                  Icons.access_time_rounded,
                                                  size: 12,
                                                  color: Colors.grey.shade400,
                                                ),
                                                const SizedBox(width: AppSpacing.xs),
                                                Text(
                                                  _formatTimeAgo(notification['createdAt']),
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    color: Colors.grey.shade500,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      // Unread indicator
                                      if (isUnread)
                                        Container(
                                          width: 8,
                                          height: 8,
                                          decoration: BoxDecoration(
                                            color: AppColors.primary,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                      if (isInvitation)
                                        Icon(
                                          Icons.chevron_right_rounded,
                                          color: Colors.grey.shade400,
                                          size: 20,
                                        ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.notifications_none_rounded,
              size: 50,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'components.notifications_screen.noNotificationsYet'.tr(),
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'components.notifications_screen.noNotificationsHint'.tr(),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: AppColors.textSecondary,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
