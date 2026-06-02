import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:loringo_app/components/content_status_badge.dart';
import 'package:loringo_app/services/database/database.dart';

class ContentApprovalScreen extends StatefulWidget {
  const ContentApprovalScreen({super.key});

  @override
  State<ContentApprovalScreen> createState() => _ContentApprovalScreenState();
}

class _ContentApprovalScreenState extends State<ContentApprovalScreen> {
  final Database _db = Database();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: StreamBuilder<List<PendingContent>>(
        // All Firestore logic lives in Database.getPendingContentStream()
        stream: _db.getPendingContentStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle_outline, size: 100, color: Colors.grey[300]),
                  const SizedBox(height: 24),
                  Text('All Caught Up!',
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.grey[800])),
                  const SizedBox(height: 12),
                  Text('No pending content to review',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16, color: Colors.grey[600])),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: snapshot.data!.length,
            itemBuilder: (context, index) {
              final content = snapshot.data![index];
              return Card(
                margin: const EdgeInsets.only(bottom: 16),
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title + status badge
                      Row(children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(content.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            Text('by ${content.teacherName}', style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                          ]),
                        ),
                        ContentStatusBadge(status: content.status, showIcon: true),
                      ]),
                      const SizedBox(height: 12),
                      // Description
                      Text(content.description,
                          style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                          maxLines: 2, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 12),
                      // Age group + date
                      Row(children: [
                        Icon(Icons.cake, size: 16, color: Colors.grey[600]),
                        const SizedBox(width: 6),
                        Text(content.ageGroup, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                        const SizedBox(width: 16),
                        Icon(Icons.calendar_today, size: 16, color: Colors.grey[600]),
                        const SizedBox(width: 6),
                        Text(content.createdAt, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                      ]),
                      const SizedBox(height: 16),
                      // Reject / Approve buttons
                      Row(children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _rejectContent(content.contentId, content.title),
                            icon: const Icon(Icons.close),
                            label: const Text('Reject'),
                            style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.red,
                                side: const BorderSide(color: Colors.red)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => _approveContent(content.contentId, content.title),
                            icon: const Icon(Icons.check),
                            label: const Text('Approve'),
                            style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green, foregroundColor: Colors.white),
                          ),
                        ),
                      ]),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _approveContent(String contentId, String title) async {
    try {
      await _db.writeContentApproved(contentId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('✅ "$title" has been approved'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error approving content: $e'),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  Future<void> _rejectContent(String contentId, String title) async {
    final reason = await showDialog<String?>(
      context: context,
      builder: (context) => RejectionReasonDialog(title: title),
    );
    if (reason == null) return;
    try {
      await _db.writeContentRejected(contentId, reason);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('❌ "$title" has been rejected'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 2),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error rejecting content: $e'),
          backgroundColor: Colors.red,
        ));
      }
    }
  }
}

// ── Model ─────────────────────────────────────────────────────────────────────

class PendingContent {
  final String contentId;
  final String title;
  final String description;
  final String ageGroup;
  final String teacherName;
  final String status;
  final String createdAt;

  const PendingContent({
    required this.contentId,
    required this.title,
    required this.description,
    required this.ageGroup,
    required this.teacherName,
    required this.status,
    required this.createdAt,
  });
}

// ── Rejection dialog ──────────────────────────────────────────────────────────

class RejectionReasonDialog extends StatefulWidget {
  final String title;
  const RejectionReasonDialog({super.key, required this.title});

  @override
  State<RejectionReasonDialog> createState() => _RejectionReasonDialogState();
}

class _RejectionReasonDialogState extends State<RejectionReasonDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Reject Content'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Why are you rejecting "${widget.title}"?', style: const TextStyle(fontSize: 14)),
        const SizedBox(height: 16),
        TextField(
          controller: _ctrl,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: 'Provide a reason for rejection (optional)',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, _ctrl.text),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
          child: const Text('Reject'),
        ),
      ],
    );
  }
}