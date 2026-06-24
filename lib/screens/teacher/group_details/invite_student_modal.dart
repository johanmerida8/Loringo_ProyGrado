import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:loringo_app/services/notifications/one_signal_service.dart';

void showInviteStudentModal({
  required BuildContext context,
  required String groupId,
  required String groupName,
  required String groupCode,
  required Color groupColor,
}) {
  final emailController = TextEditingController();

  void copyCodeToClipboard(BuildContext modalContext) {
    Clipboard.setData(ClipboardData(text: groupCode));
    ScaffoldMessenger.of(modalContext).showSnackBar(
      const SnackBar(
        content: Text('✅ Code copied to clipboard'),
        backgroundColor: Color(0xFF4CAF50),
        duration: Duration(seconds: 2),
      ),
    );
  }

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (modalContext) => Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(25)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(modalContext).viewInsets.bottom + 20,
        left: 24,
        right: 24,
        top: 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ModalHeader(
              groupColor: groupColor,
              onClose: () {
                emailController.dispose();
                Navigator.pop(modalContext);
              },
            ),
            const SizedBox(height: 24),
            _ShareCodeHint(groupColor: groupColor),
            const SizedBox(height: 24),
            _GroupCodeCard(
              groupColor: groupColor,
              groupCode: groupCode,
              groupName: groupName,
            ),
            const SizedBox(height: 20),
            _CopyCodeButton(
              groupColor: groupColor,
              onCopy: () => copyCodeToClipboard(modalContext),
            ),
            const SizedBox(height: 24),
            const _OrDivider(),
            const SizedBox(height: 24),
            _SendInvitationSection(
              emailController: emailController,
              groupColor: groupColor,
              groupId: groupId,
              groupName: groupName,
              groupCode: groupCode,
              onSent: () {
                emailController.dispose();
                Navigator.pop(modalContext);
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    ),
  );
}

class _ModalHeader extends StatelessWidget {
  const _ModalHeader({required this.groupColor, required this.onClose});

  final Color groupColor;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Icon(Icons.person_add, color: groupColor, size: 28),
            const SizedBox(width: 12),
            const Text(
              'Invite Student',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
          ],
        ),
        IconButton(
          onPressed: onClose,
          icon: const Icon(Icons.close),
          color: Colors.grey[600],
        ),
      ],
    );
  }
}

class _ShareCodeHint extends StatelessWidget {
  const _ShareCodeHint({required this.groupColor});

  final Color groupColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: groupColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: groupColor.withOpacity(0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: groupColor),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Share this code with your students',
              style: TextStyle(fontSize: 14, color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupCodeCard extends StatelessWidget {
  const _GroupCodeCard({
    required this.groupColor,
    required this.groupCode,
    required this.groupName,
  });

  final Color groupColor;
  final String groupCode;
  final String groupName;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [groupColor, groupColor.withOpacity(0.8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: groupColor.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          const Text(
            'Group Code',
            style: TextStyle(
              fontSize: 14,
              color: Colors.white70,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            groupCode,
            style: const TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              letterSpacing: 4,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            groupName,
            style: const TextStyle(fontSize: 14, color: Colors.white70),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _CopyCodeButton extends StatelessWidget {
  const _CopyCodeButton({required this.groupColor, required this.onCopy});

  final Color groupColor;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onCopy,
        icon: const Icon(Icons.copy_rounded),
        label: const Text(
          'Copy Code',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: groupColor,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
        ),
      ),
    );
  }
}

class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Divider(color: Colors.grey[300])),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'OR',
            style: TextStyle(
              color: Colors.grey[600],
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Expanded(child: Divider(color: Colors.grey[300])),
      ],
    );
  }
}

class _SendInvitationSection extends StatelessWidget {
  const _SendInvitationSection({
    required this.emailController,
    required this.groupColor,
    required this.groupId,
    required this.groupName,
    required this.groupCode,
    required this.onSent,
  });

  final TextEditingController emailController;
  final Color groupColor;
  final String groupId;
  final String groupName;
  final String groupCode;
  final VoidCallback onSent;

  static final RegExp _emailPattern =
      RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');

  Future<void> _sendInvitation(BuildContext context) async {
    final email = emailController.text.trim();
    if (email.isEmpty) {
      _showWarning(context, 'Please enter an email');
      return;
    }
    if (!_emailPattern.hasMatch(email)) {
      _showWarning(context, 'Please enter a valid email');
      return;
    }

    try {
      final userSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: email)
          .where('role', isEqualTo: 'parent')
          .limit(1)
          .get();

      if (!context.mounted) return;
      if (userSnapshot.docs.isEmpty) {
        _showWarning(context, 'No parent found with that email');
        return;
      }

      final parentId = userSnapshot.docs.first.id;
      await FirebaseFirestore.instance.collection('notifications').add({
        'userId': parentId,
        'type': 'group_invitation',
        'title': 'Group Invitation',
        'message': 'You have been invited to the group $groupName',
        'data': {
          'groupId': groupId,
          'groupName': groupName,
          'groupCode': groupCode,
        },
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // send push notification
      await OneSignalNotificationService.sendNotification(
        userId: parentId, 
        title: 'Group Invitation', 
        message: 'You have been invited to the group $groupName'
      );

      if (!context.mounted) return;
      onSent();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Invitation sent to $email'),
          backgroundColor: const Color(0xFF4CAF50),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showWarning(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.orange),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Send Direct Invitation',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.grey[800],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Enter parent\'s email to send a group invitation',
          style: TextStyle(fontSize: 13, color: Colors.grey[600]),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: emailController,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(
            labelText: 'Parent Email',
            hintText: 'example@email.com',
            prefixIcon: const Icon(Icons.email_outlined),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey[300]!),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: groupColor, width: 2),
            ),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => _sendInvitation(context),
            icon: const Icon(Icons.send_rounded),
            label: const Text(
              'Send Invitation',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green[600],
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
            ),
          ),
        ),
      ],
    );
  }
}
