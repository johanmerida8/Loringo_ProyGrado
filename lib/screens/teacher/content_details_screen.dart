import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:loringo_app/screens/teacher/create_unit_screen.dart';
import 'package:loringo_app/screens/teacher/lesson_list_screen.dart';
import 'package:loringo_app/services/database/database.dart';

class PersonalizedContentDetailsScreen extends StatefulWidget {
  final String groupId;
  final String contentId;
  final String contentTitle;
  final Color groupColor;

  const PersonalizedContentDetailsScreen({
    super.key,
    required this.groupId,
    required this.contentId,
    required this.contentTitle,
    required this.groupColor,
  });

  @override
  State<PersonalizedContentDetailsScreen> createState() =>
      _PersonalizedContentDetailsScreenState();
}

class _PersonalizedContentDetailsScreenState
    extends State<PersonalizedContentDetailsScreen> {
  final db = Database();

  @override
  void initState() {
    super.initState();
    _getContentStatusStream(); // Start listening to content status updates
  }

  Stream<Map<String, dynamic>> _getContentStatusStream() {
    return db.personalizedContent
        .doc(widget.contentId)
        .snapshots()
        .asyncMap((doc) async {
          if (!doc.exists) {
            return {'status': 'pending', 'rejectionReason': null};
          }
          final data = doc.data() as Map<String, dynamic>;
          final status = data['status'] ?? 'pending';

          String? rejectionReason;
          if (status == 'rejected') {
            final approvalDoc =
                await db.getContentApprovalRecord(widget.contentId);
            if (approvalDoc.exists) {
              final approvalData =
                  approvalDoc.data() as Map<String, dynamic>?;
              rejectionReason = approvalData?['reason'] as String?;
            }
          }

          return {
            'status': status,
            'rejectionReason': rejectionReason,
          };
        });
  }

  Widget _buildRejectionMessage(String? reason) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.red[50],
              border: Border.all(color: Colors.red[300]!, width: 1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.cancel, color: Colors.red[700], size: 24),
                    const SizedBox(width: 12),
                    Text(
                      'Rejected',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.red[700],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'Admin Feedback:',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.red[600],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  reason ?? 'No reason provided',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.red[700],
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: _editRejectedContent,
                  icon: const Icon(Icons.edit),
                  label: const Text('Edit & Resubmit'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red[700],
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPendingMessage() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.schedule, size: 80, color: Colors.orange[200]),
          const SizedBox(height: 16),
          Text(
            'Awaiting Approval',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.orange[700],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Your content is pending admin review',
            style: TextStyle(fontSize: 14, color: Colors.grey[600]),
          ),
          const SizedBox(height: 8),
          Text(
            'You can still edit units while waiting',
            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  Widget _buildUnitsList() {
    return StreamBuilder<QuerySnapshot>(
      stream: db.getPersonalizedUnitsStream(widget.groupId, widget.contentId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          print('[ContentDetails] ❌ Error fetching units | contentId: ${widget.contentId} | error: ${snapshot.error}');
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          print('[ContentDetails] No units found | contentId: ${widget.contentId} | groupId: ${widget.groupId}');
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.layers_outlined, size: 80, color: Colors.grey[300]),
                const SizedBox(height: 16),
                Text(
                  'No Units Yet',
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Create the first unit to get started',
                  style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CreatePersonalizedUnitScreen(
                        groupId: widget.groupId,
                        contentId: widget.contentId,
                        groupColor: widget.groupColor,
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.add),
                  label: const Text('Create First Unit'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: widget.groupColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        final units = snapshot.data!.docs;
        print('[ContentDetails] ✅ Units fetched | contentId: ${widget.contentId} | count: ${units.length}');

        return ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: units.length,
          separatorBuilder: (_, __) => Divider(
            height: 1,
            indent: 64,
            color: Colors.grey[100],
          ),
          itemBuilder: (context, index) {
            final unitDoc = units[index];
            final unitData = unitDoc.data() as Map<String, dynamic>;
            final title = unitData['title'] ?? 'Untitled';
            final order = unitData['order'] ?? 0;

            return ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              leading: Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: widget.groupColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  order.toString(),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: widget.groupColor,
                    fontSize: 15,
                  ),
                ),
              ),
              title: Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PersonalizedLessonListScreen(
                      groupId: widget.groupId,
                      contentId: widget.contentId,
                      unitId: unitDoc.id,
                      unitTitle: title,
                      groupColor: widget.groupColor,
                    ),
                  ),
                );
              },
              trailing: PopupMenuButton(
                itemBuilder: (context) => [
                  PopupMenuItem(
                    child: const Row(
                      children: [
                        Icon(Icons.edit, color: Colors.blue),
                        SizedBox(width: 8),
                        Text('Edit'),
                      ],
                    ),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => CreatePersonalizedUnitScreen(
                            groupId: widget.groupId,
                            contentId: widget.contentId,
                            unitId: unitDoc.id,
                            existingData: unitData,
                            groupColor: widget.groupColor,
                          ),
                        ),
                      );
                    },
                  ),
                  PopupMenuItem(
                    child: const Row(
                      children: [
                        Icon(Icons.delete, color: Colors.red),
                        SizedBox(width: 8),
                        Text('Delete'),
                      ],
                    ),
                    onTap: () => _deleteUnit(unitDoc.id, title),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: widget.groupColor,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.contentTitle,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            const Text(
              'Units',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: StreamBuilder<Map<String, dynamic>>(
        stream: _getContentStatusStream(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final contentData = snapshot.data!;
          final status = contentData['status'] as String;
          final rejectionReason = contentData['rejectionReason'] as String?;

          // Content based on status
          return status == 'rejected'
              ? _buildRejectionMessage(rejectionReason)
              : status == 'pending'
                  ? _buildPendingMessage()
                  : _buildUnitsList();
        },
      ),
      floatingActionButton: StreamBuilder<Map<String, dynamic>>(
        stream: _getContentStatusStream(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const SizedBox.shrink();
          
          final status = snapshot.data!['status'] as String;
          
          // Only show FAB if content is approved
          if (status != 'approved') return const SizedBox.shrink();
          
          return FloatingActionButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CreatePersonalizedUnitScreen(
                    groupId: widget.groupId,
                    contentId: widget.contentId,
                    groupColor: widget.groupColor,
                  ),
                ),
              );
            },
            backgroundColor: widget.groupColor,
            child: const Icon(Icons.add, color: Colors.white),
          );
        },
      ),
    );
  }

  void _editRejectedContent() {
    Navigator.pop(context);
  }

  Future<void> _deleteUnit(String unitId, String title) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Unit'),
        content: Text('Are you sure you want to delete "$title"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await db.deletePersonalizedUnit(
          widget.groupId,
          widget.contentId,
          unitId,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Unit deleted successfully'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error deleting unit: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }
}
