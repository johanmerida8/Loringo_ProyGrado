// parent_children_screen.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:loringo_app/providers/locale_provider.dart';
import 'package:loringo_app/screens/parent/parent_child_activity_status_screen.dart';
import 'package:loringo_app/screens/parent/parent_child_progress_path_screen.dart';
import 'package:loringo_app/screens/parent/parent_join_group_screen.dart';
import 'package:loringo_app/screens/parent/parent_register_child_screen.dart';
import 'package:loringo_app/components/avatar_image.dart';
import 'package:loringo_app/services/auth/identity_confirmation.dart';
import 'package:loringo_app/services/database/database.dart';
import 'package:loringo_app/services/firebase_refs.dart';
import 'package:loringo_app/theme/app_theme.dart';
import 'package:loringo_app/utils/access_code_hasher.dart';

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

  /// The access code is static (set once at registration, never rotated)
  /// and is never stored as recoverable plaintext (see database.dart's
  /// STUDENTS section) — only encrypted. This decrypts it back for
  /// display, gated behind identity confirmation (biometric, with password
  /// fallback — see identity_confirmation.dart) since it hands back the
  /// real code in the clear.
  Future<void> _revealAccessCodeFlow(
      BuildContext context, Map<String, dynamic> child) async {
    final confirmed = await confirmIdentity(
      context,
      reason: 'common.confirmIdentityBody'.tr(),
    );
    if (!confirmed || !context.mounted) return;

    String accessCode;
    try {
      accessCode = await Database(firestore: firestoreInstance)
          .revealAccessCode(child['id'] as String);
      // ignore: avoid_print
      print('[REVEAL CODE] student=${child['id']} code=$accessCode '
          'hash=${AccessCodeHasher.hash(accessCode)}');
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${'common.error'.tr()}: $e'),
          backgroundColor: Colors.red,
        ));
      }
      return;
    }

    if (context.mounted) {
      _showAccessCodeDialog(context, child, accessCode);
    }
  }

  void _showAccessCodeDialog(
      BuildContext context, Map<String, dynamic> child, String accessCode) {
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
              child: Text(
                  'parent.parent_children_screen.childsCode'
                      .tr(namedArgs: {'name': '${child['names']}'}),
                  style: const TextStyle(fontSize: 18)),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'common.shareCodeToChild'.tr(),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14),
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
                    SnackBar(
                  content: Text('common.codeCopied'.tr()),
                  backgroundColor: Colors.green,
                  duration: const Duration(seconds: 2),
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
              label: Text('common.copyCode'.tr()),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('common.close'.tr()),
          ),
        ],
      ),
    );
  }

  /// Permanently removes a single child — deletes their profile and every
  /// group's progress/reports for them (see
  /// Database.deleteStudentCascade), but leaves groups/teachers
  /// untouched. Distinct from deleting the whole parent account
  /// (parent_navigation_screen.dart), which loops this same cascade over
  /// every child.
  Future<void> _removeChildFlow(
      BuildContext context, Map<String, dynamic> child) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('parent.parent_children_screen.removeChildTitle'.tr()),
        content: Text('parent.parent_children_screen.removeChildMsg'
            .tr(namedArgs: {'name': '${child['names']}'})),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('common.cancel'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('common.delete'.tr(),
                style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      await Database(firestore: firestoreInstance)
          .deleteStudentCascade(child['id'] as String);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('parent.parent_children_screen.childRemoved'
              .tr(namedArgs: {'name': '${child['names']}'})),
          backgroundColor: Colors.green,
        ));
      }
      onRefresh();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${'common.error'.tr()}: $e'),
          backgroundColor: Colors.red,
        ));
      }
    }
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

  void _navigateToActivityStatus(
      BuildContext context, Map<String, dynamic> child) {
    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (context) =>
              ParentChildActivityStatusScreen(child: child)),
    );
  }

  void _navigateToProgressPath(
      BuildContext context, Map<String, dynamic> child) {
    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (context) =>
              ParentChildProgressPathScreen(child: child)),
    );
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LocaleProvider>();
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Inline header ──
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
            child: Text(
              'common.myChildren'.tr(),
              style: const TextStyle(
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
                label: Text('common.addChild'.tr(),
                    style: const TextStyle(
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
                        child['names'] ?? 'common.noName'.tr(),
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
                                    'parent.parent_children_screen.loadingGroup'
                                        .tr()
                                : 'common.noGroupAssigned'.tr(),
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
                IconButton(
                  onPressed: () => _removeChildFlow(context, child),
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  tooltip: 'parent.parent_children_screen.removeChildTitle'.tr(),
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
                      label: 'common.joinGroup'.tr(),
                      isPrimary: true,
                      onPressed: () =>
                          _navigateToJoinGroup(context, child),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                if (hasGroup) ...[
                  Expanded(
                    child: _actionButton(
                      icon: Icons.checklist_rounded,
                      label: 'parent.parent_children_screen.activities'.tr(),
                      isPrimary: true,
                      onPressed: () =>
                          _navigateToActivityStatus(context, child),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: _actionButton(
                    icon: Icons.key_rounded,
                    label: 'common.accessCode'.tr(),
                    isPrimary: false,
                    onPressed: () =>
                        _revealAccessCodeFlow(context, child),
                  ),
                ),
              ],
            ),
            if (hasGroup) ...[
              const SizedBox(height: 10),
              _actionButton(
                icon: Icons.route_rounded,
                label: 'parent.parent_children_screen.viewLearningPath'.tr(),
                isPrimary: false,
                onPressed: () => _navigateToProgressPath(context, child),
              ),
            ],
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
        backgroundImage: avatarImageProvider(avatar),
        onBackgroundImageError: (_, __) {},
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
            Text('common.noChildRegistered'.tr(),
                style: TextStyle(
                    fontSize: 15, color: Colors.grey[500])),
          ],
        ),
      ),
    );
  }
}