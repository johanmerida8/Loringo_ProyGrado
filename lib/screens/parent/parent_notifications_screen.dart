import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
// import 'package:intl/intl.dart';

/// Parent Notifications Screen
/// Shows all notifications for the parent
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
          .get();

      final notifs = notificationsSnapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();

      // Sort by createdAt descending (newest first) in the app
      notifs.sort((a, b) {
        final aTime = a['createdAt'] as Timestamp?;
        final bTime = b['createdAt'] as Timestamp?;
        if (aTime == null && bTime == null) return 0;
        if (aTime == null) return 1;
        if (bTime == null) return -1;
        return bTime.compareTo(aTime); // Descending order
      });

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

  /// Handle group invitation notification
  Future<void> _handleGroupInvitation(Map<String, dynamic> notification) async {
    final data = notification['data'];
    if (data == null) return;

    final groupCode = data['groupCode'] as String?;
    final groupName = data['groupName'] as String?;

    if (groupCode == null) return;

    // Mark notification as read
    await FirebaseFirestore.instance
        .collection('notifications')
        .doc(notification['id'])
        .update({'isRead': true});

    // Show dialog to select which child to join
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ You have no registered children'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Filter students not in a group
    final availableStudents = students
        .where((s) => s['groupId'] == null || s['groupId'].isEmpty)
        .toList();

    if (availableStudents.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ All your children are already in a group'),
          backgroundColor: Color(0xFFA2CA71),
        ),
      );
      return;
    }

    // Show selection dialog
    final selectedStudentId = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Join group "$groupName"'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Select the child you want to join:'),
            const SizedBox(height: 16),
            ...availableStudents.map(
              (student) => ListTile(
                leading: CircleAvatar(
                  backgroundImage: student['avatar'] != null
                      ? AssetImage(student['avatar'])
                      : null,
                  child: student['avatar'] == null
                      ? Text(
                          student['names'] != null &&
                                  student['names'].isNotEmpty
                              ? student['names'][0].toUpperCase()
                              : 'S',
                        )
                      : null,
                ),
                title: Text(student['names'] ?? 'No name'),
                onTap: () => Navigator.pop(context, student['id']),
              ),
            ),
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

    // Join student to group
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

      // Create subcollection entry in the group using student UID
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✅ ${student['names']} joined the group "$groupName"',
            ),
            backgroundColor: const Color(0xFFA2CA71),
          ),
        );
        _loadNotifications();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  String _formatTimeAgo(Timestamp? timestamp) {
    if (timestamp == null) return '';

    final date = timestamp.toDate();
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAEDCA),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFFCFB3),
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(
            context,
            true,
          ), // Return true to refresh parent screen
          icon: const Icon(Icons.arrow_back, color: Colors.white),
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
              onPressed: () async {
                if (parentUserId != null) {
                  final batch = FirebaseFirestore.instance.batch();
                  final unreadNotifs = notifications.where(
                    (n) => n['isRead'] == false,
                  );

                  for (var notif in unreadNotifs) {
                    final docRef = FirebaseFirestore.instance
                        .collection('notifications')
                        .doc(notif['id']);
                    batch.update(docRef, {'isRead': true});
                  }

                  await batch.commit();
                  _loadNotifications();
                }
              },
              icon: const Icon(Icons.done_all, color: Colors.white, size: 18),
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
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.notifications_none_rounded,
                    size: 100,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No notifications',
                    style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadNotifications,
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: notifications.length,
                itemBuilder: (context, index) {
                  final notification = notifications[index];
                  final isUnread = notification['isRead'] == false;

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: isUnread
                          ? const BorderSide(color: Color(0xFFFE5D26), width: 2)
                          : BorderSide.none,
                    ),
                    elevation: isUnread ? 4 : 2,
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(16),
                      leading: Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: isUnread
                              ? const Color(0xFFFE5D26)
                              : Colors.grey[300],
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          notification['type'] == 'group_invitation'
                              ? Icons.group_add_rounded
                              : notification['type'] == 'teacher_message'
                              ? Icons.message_rounded
                              : Icons.notifications_rounded,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                      title: Text(
                        notification['title'] ?? 'Notification',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: isUnread
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 4),
                          Text(
                            notification['message'] ?? '',
                            style: const TextStyle(fontSize: 14),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _formatTimeAgo(notification['createdAt']),
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                      trailing: notification['type'] == 'group_invitation'
                          ? const Icon(Icons.arrow_forward_ios, size: 16)
                          : null,
                      onTap: () {
                        if (notification['type'] == 'group_invitation') {
                          _handleGroupInvitation(notification);
                        } else if (isUnread && notification['id'] != null) {
                          FirebaseFirestore.instance
                              .collection('notifications')
                              .doc(notification['id'])
                              .update({'isRead': true});
                          _loadNotifications();
                        }
                      },
                    ),
                  );
                },
              ),
            ),
    );
  }
}
