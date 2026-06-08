import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:loringo_app/theme/app_theme.dart';

class ParentNotificationsScreen extends StatefulWidget {
  const ParentNotificationsScreen({super.key});

  @override
  State<ParentNotificationsScreen> createState() =>
      _ParentNotificationsScreenState();
}

class _ParentNotificationsScreenState extends State<ParentNotificationsScreen> {
  List<Map<String, dynamic>> notifications = [];
  bool isLoading = true;
  String? parentUserId;

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

      parentUserId = currentUser.uid;

      final notificationsSnapshot = await FirebaseFirestore.instance
          .collection('notifications')
          .where('userId', isEqualTo: parentUserId)
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
          SnackBar(content: Text('Error loading notifications: $e')),
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
    if (parentUserId == null) return;
    
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
        .where('parentId', isEqualTo: parentUserId)
        .get();

    final students = studentsSnapshot.docs.map((doc) {
      final data = doc.data();
      data['id'] = doc.id;
      return data;
    }).toList();

    if (students.isEmpty) {
      _showSnackBar('You have no registered children', Colors.red);
      return;
    }

    final availableStudents = students
        .where((s) => s['groupId'] == null || s['groupId'].isEmpty)
        .toList();

    if (availableStudents.isEmpty) {
      _showSnackBar('All your children are already in a group', 
          const Color(0xFFA2CA71));
      return;
    }

    final selectedStudentId = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Join "$groupName"'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Select a child:'),
            const SizedBox(height: 16),
            ...availableStudents.map((student) => ListTile(
              leading: CircleAvatar(
                backgroundColor: AppColors.primary.withOpacity(0.1),
                child: Text(
                  (student['names'] as String? ?? 'C')[0].toUpperCase(),
                  style: TextStyle(color: AppColors.primary),
                ),
              ),
              title: Text(student['names'] ?? 'No name'),
              onTap: () => Navigator.pop(context, student['id']),
            )),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    if (selectedStudentId == null) return;

    try {
      final groupSnapshot = await FirebaseFirestore.instance
          .collection('teacherGroups')
          .where('groupCode', isEqualTo: groupCode)
          .get();

      if (groupSnapshot.docs.isEmpty) {
        throw Exception('Group not found');
      }

      final groupId = groupSnapshot.docs.first.id;
      final student = availableStudents.firstWhere(
        (s) => s['id'] == selectedStudentId,
      );

      await FirebaseFirestore.instance
          .collection('students')
          .doc(selectedStudentId)
          .update({'groupId': groupId});

      await FirebaseFirestore.instance
          .collection('teacherGroups')
          .doc(groupId)
          .collection('students')
          .doc(selectedStudentId)
          .set({
            'studentId': selectedStudentId,
            'joinedAt': FieldValue.serverTimestamp(),
          });

      if (mounted) {
        _showSnackBar('${student['names']} joined "$groupName"', 
            const Color(0xFFA2CA71));
        _loadNotifications();
      }
    } catch (e) {
      _showSnackBar('Error: $e', Colors.red);
    }
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color),
    );
  }

  String _formatTimeAgo(Timestamp? timestamp) {
    if (timestamp == null) return '';
    final date = timestamp.toDate();
    final difference = DateTime.now().difference(date);

    if (difference.inDays > 0) return '${difference.inDays}d ago';
    if (difference.inHours > 0) return '${difference.inHours}h ago';
    if (difference.inMinutes > 0) return '${difference.inMinutes}m ago';
    return 'Just now';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAEDCA),
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context, true),
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
        ),
        title: const Text(
          'Notifications',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        actions: [
          if (notifications.any((n) => n['isRead'] == false))
            TextButton.icon(
              onPressed: _markAllAsRead,
              icon: const Icon(Icons.done_all_rounded, color: Colors.white, size: 18),
              label: const Text(
                'Mark all',
                style: TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : notifications.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  onRefresh: _loadNotifications,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
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
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: isUnread
                                ? Border.all(color: AppColors.primary, width: 2)
                                : null,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.05),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Icon
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: isUnread
                                      ? AppColors.primary.withOpacity(0.1)
                                      : Colors.grey[100],
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  isInvitation
                                      ? Icons.group_add_rounded
                                      : type == 'quiz_report'
                                          ? Icons.quiz_rounded
                                          : Icons.notifications_rounded,
                                  color: isUnread ? AppColors.primary : Colors.grey[400],
                                  size: 24,
                                ),
                              ),
                              const SizedBox(width: 12),
                              // Content
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      notification['title'] ?? 'Notification',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: isUnread
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                        color: isUnread ? Colors.black87 : Colors.grey[600],
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      notification['message'] ?? '',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      _formatTimeAgo(notification['createdAt']),
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey[500],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // Unread dot
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
                                const Icon(
                                  Icons.chevron_right_rounded,
                                  color: Colors.grey,
                                  size: 20,
                                ),
                            ],
                          ),
                        ),
                      );
                    },
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
          const SizedBox(height: 24),
          Text(
            'No notifications yet',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'When you receive notifications,\nthey will appear here',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }
}