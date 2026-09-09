import 'package:cloud_functions/cloud_functions.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:loringo_app/services/database/database.dart';

void showInviteStudentModal({
  required BuildContext context,
  required String groupId,
  required String groupName,
  required Color groupColor,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (modalContext) => _InviteStudentModalBody(
      groupId: groupId,
      groupName: groupName,
      groupColor: groupColor,
    ),
  );
}

// Owns emailController itself (created/disposed via normal State
// lifecycle) instead of a controller created in the plain function above
// and disposed manually from onClose/onSent. Manual disposal raced the
// sheet's closing animation — the Future showModalBottomSheet returns
// resolves as soon as Navigator.pop() is *called*, not once the sheet has
// actually finished animating out and left the tree, so disposing there
// (directly, or via .then() on that Future) tore the controller down
// while the TextField was still being rebuilt for the outgoing frames,
// throwing "A TextEditingController was used after being disposed." A
// State's dispose() is only ever called once its Element is truly
// unmounted, which naturally happens after the animation — the correct
// timing, for free, by just letting Flutter own the lifecycle.
class _InviteStudentModalBody extends StatefulWidget {
  const _InviteStudentModalBody({
    required this.groupId,
    required this.groupName,
    required this.groupColor,
  });

  final String groupId;
  final String groupName;
  final Color groupColor;

  @override
  State<_InviteStudentModalBody> createState() =>
      _InviteStudentModalBodyState();
}

class _InviteStudentModalBodyState extends State<_InviteStudentModalBody> {
  late final TextEditingController _emailController = TextEditingController();
  String? _groupCode;
  bool _loading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _loadGroupCode();
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  /// The group code is never stored in plaintext (see
  /// functions/src/groupCode.ts) — fetched on demand here, decrypted
  /// server-side, only for the owning teacher.
  Future<void> _loadGroupCode() async {
    setState(() {
      _loading = true;
      _hasError = false;
    });
    try {
      final code = await Database().revealGroupCode(widget.groupId);
      if (mounted) setState(() => _groupCode = code);
    } catch (_) {
      if (mounted) setState(() => _hasError = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _copyCodeToClipboard(BuildContext modalContext) {
    final code = _groupCode;
    if (code == null) return;
    Clipboard.setData(ClipboardData(text: code));
    ScaffoldMessenger.of(modalContext).showSnackBar(
      SnackBar(
        content: Text('teacher.group_navigation_screen.codeCopied'.tr()),
        backgroundColor: const Color(0xFF4CAF50),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
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
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
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
              groupColor: widget.groupColor,
              onClose: () => Navigator.pop(context),
            ),
            const SizedBox(height: 24),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_hasError || _groupCode == null)
              _CodeLoadError(onRetry: _loadGroupCode)
            else ...[
              _ShareCodeHint(groupColor: widget.groupColor),
              const SizedBox(height: 24),
              _GroupCodeCard(
                groupColor: widget.groupColor,
                groupCode: _groupCode!,
                groupName: widget.groupName,
              ),
              const SizedBox(height: 20),
              _CopyCodeButton(
                groupColor: widget.groupColor,
                onCopy: () => _copyCodeToClipboard(context),
              ),
              const SizedBox(height: 24),
              const _OrDivider(),
              const SizedBox(height: 24),
              _SendInvitationSection(
                emailController: _emailController,
                groupColor: widget.groupColor,
                groupId: widget.groupId,
                groupName: widget.groupName,
                groupCode: _groupCode!,
                onSent: () => Navigator.pop(context),
              ),
            ],
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

class _CodeLoadError extends StatelessWidget {
  const _CodeLoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Icon(Icons.cloud_off_rounded, color: Colors.grey[400], size: 40),
          const SizedBox(height: 12),
          Text(
            'teacher.invite_student_modal.loadCodeFailed'.tr(),
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[600]),
          ),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: Text('common.retry'.tr())),
        ],
      ),
    );
  }
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
            Text(
              'teacher.invite_student_modal.title'.tr(),
              style: const TextStyle(
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
          Expanded(
            child: Text(
              'teacher.invite_student_modal.shareCodeHint'.tr(),
              style: const TextStyle(fontSize: 14, color: Colors.black87),
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
          Text(
            'teacher.invite_student_modal.groupCodeLabel'.tr(),
            style: const TextStyle(
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
        label: Text(
          'teacher.invite_student_modal.copyCode'.tr(),
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
            'teacher.invite_student_modal.or'.tr(),
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

class _SendInvitationSection extends StatefulWidget {
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

  @override
  State<_SendInvitationSection> createState() => _SendInvitationSectionState();
}

class _SendInvitationSectionState extends State<_SendInvitationSection> {
  static final RegExp _emailPattern =
      RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');

  String? _message;
  Color _messageColor = Colors.orange;
  bool _sending = false;

  Future<void> _sendInvitation() async {
    final email = widget.emailController.text.trim();
    if (email.isEmpty) {
      _showMessage('common.emailValidation1'.tr(), Colors.orange);
      return;
    }
    if (!_emailPattern.hasMatch(email)) {
      _showMessage('common.emailValidation2'.tr(), Colors.orange);
      return;
    }

    setState(() {
      _sending = true;
      _message = null;
    });

    try {
      // Parent lookup, the notifications-history write, and the OneSignal
      // push all now happen server-side in one call — see
      // functions/src/groupInvitationNotifications.ts. This used to be
      // three separate client-side steps here, duplicating the exact
      // pattern notification_service.dart used for report notifications;
      // consolidating both onto Cloud Functions callables removed that
      // duplication.
      final callable = FirebaseFunctions.instance.httpsCallable('sendGroupInvitationNotification');
      await callable.call({
        'parentEmail': email,
        'groupId': widget.groupId,
        'groupName': widget.groupName,
        'groupCode': widget.groupCode,
      });

      if (!mounted) return;
      _showMessage(
          'teacher.invite_student_modal.invitationSent'
              .tr(namedArgs: {'email': email}),
          const Color(0xFF4CAF50));
      await Future.delayed(const Duration(milliseconds: 900));
      if (!mounted) return;
      widget.onSent();
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      if (e.code == 'not-found') {
        _showMessage(
            'teacher.invite_student_modal.noParentFound'.tr(), Colors.orange);
        return;
      }
      _showMessage(
          'common.errorWithMessage'.tr(namedArgs: {'error': e.message ?? e.code}),
          Colors.red);
    } catch (e) {
      if (!mounted) return;
      _showMessage(
          'common.errorWithMessage'.tr(namedArgs: {'error': '$e'}), Colors.red);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _showMessage(String message, Color color) {
    setState(() {
      _message = message;
      _messageColor = color;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'teacher.invite_student_modal.sendDirectInvitation'.tr(),
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.grey[800],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'teacher.invite_student_modal.enterParentEmail'.tr(),
          style: TextStyle(fontSize: 13, color: Colors.grey[600]),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: widget.emailController,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(
            labelText: 'teacher.invite_student_modal.parentEmailFieldLabel'.tr(),
            hintText: 'teacher.invite_student_modal.emailHint'.tr(),
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
              borderSide: BorderSide(color: widget.groupColor, width: 2),
            ),
          ),
        ),
        if (_message != null) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: _messageColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _messageColor.withOpacity(0.3)),
            ),
            child: Text(
              _message!,
              style: TextStyle(
                fontSize: 13,
                color: _messageColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _sending ? null : _sendInvitation,
            icon: _sending
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.send_rounded),
            label: Text(
              'teacher.invite_student_modal.sendInvitation'.tr(),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
