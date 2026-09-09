import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:loringo_app/providers/locale_provider.dart';
import 'package:loringo_app/screens/parent/widgets/parent_screen_header.dart';
import 'package:loringo_app/services/database/database.dart';
import 'package:loringo_app/services/firebase_refs.dart';
import 'package:loringo_app/theme/app_theme.dart';

/// Parent Join Group Screen
/// Parent enters group code to join their child to the group
///
/// COLOR MIGRATION: this screen previously used a standalone warm
/// palette (peach/cream — 0xFFFAEDCA, 0xFFFFCFB3, 0xFFB7E0FF,
/// 0xFFFE5D26, 0xFFA2CA71) that predated app_theme.dart and had no
/// tokens of its own. Every one of those is replaced below with the
/// nearest semantic AppColors token:
///   - scaffold background (0xFFFAEDCA) -> AppColors.scaffoldBackground
///   - primary action (0xFFFFCFB3)         -> AppColors.primary
///   - info card (0xFFB7E0FF)              -> AppColors.info
///   - heading/accent text (0xFFFE5D26)    -> AppColors.primaryDark
///   - success snackbar/banner (0xFFA2CA71)-> AppColors.success
///
/// HEADER CHANGE: the solid-color Scaffold.appBar is removed in favor
/// of the same inline header pattern used by ParentProfileScreen and
/// ParentRegisterChildScreen — a circular back button + large title
/// sitting directly on the scaffold background, no AppBar strip. This
/// makes all three pushed parent screens visually consistent instead
/// of this one alone keeping a solid green bar.
class ParentJoinGroupScreen extends StatefulWidget {
  final Map<String, dynamic> child;

  const ParentJoinGroupScreen({super.key, required this.child});

  @override
  State<ParentJoinGroupScreen> createState() => _ParentJoinGroupScreenState();
}

class _ParentJoinGroupScreenState extends State<ParentJoinGroupScreen> {
  final groupCodeController = TextEditingController();
  bool isLoading = false;

  @override
  void dispose() {
    groupCodeController.dispose();
    super.dispose();
  }

  /// Join child to group using group code
  void _joinGroup() async {
    if (groupCodeController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('common.enterGroupCode'.tr())),
      );
      return;
    }

    setState(() => isLoading = true);

    try {
      // Find group by code — hashed/verified server-side, see
      // functions/src/groupCode.ts (the group code is never stored in
      // plaintext, so this can't be a direct Firestore query anymore).
      final group = await Database(firestore: firestoreInstance)
          .findGroupByCode(groupCodeController.text.trim().toUpperCase());

      if (group == null) {
        throw Exception('parent.parent_join_group_screen.invalidCode'.tr());
      }

      if (group['archived'] == true) {
        throw Exception('parent.parent_join_group_screen.groupNotAccepting'.tr());
      }
      final groupId = group['groupId'] as String;
      final groupName = group['name'] as String;
      final studentId = widget.child['id'];

      // If the student was already in a different group, mark that
      // membership as left before switching — their XP/progress/reports
      // stay exactly where they are under the old group, untouched. The
      // student starts fresh under the new group.
      final studentSnapshot =
          await firestoreInstance.collection('students').doc(studentId).get();
      final previousGroupId = studentSnapshot.data()?['groupId'] as String?;

      await Database(firestore: firestoreInstance).switchGroup(
        studentId: studentId,
        oldGroupId: previousGroupId,
        newGroupId: groupId,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✅ ${'parent.parent_join_group_screen.joinedGroup'.tr(namedArgs: {
                'name': '${widget.child['names']}',
                'group': groupName,
              })}',
            ),
            backgroundColor: AppColors.success,
          ),
        );
        Navigator.pop(context, true); // Return true to indicate success
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ ${'common.errorWithMessage'.tr(namedArgs: {'error': '$e'})}'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } finally {
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LocaleProvider>();
    return Scaffold(
      // NOTE: no Scaffold.appBar — replaced with ParentScreenHeader below,
      // matching every other screen pushed from My Children.
      backgroundColor: AppColors.scaffoldBackground,
      body: Column(
        children: [
          ParentScreenHeader(title: 'common.joinGroup'.tr()),
          Expanded(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Info Card
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      decoration: BoxDecoration(
                        color: AppColors.tint(AppColors.info, 0.12),
                        borderRadius: AppRadii.lgAll,
                        border: Border.all(color: AppColors.info, width: 2),
                      ),
                      child: Column(
                        children: [
                          const Icon(
                            Icons.school_rounded,
                            size: 60,
                            color: AppColors.info,
                          ),
                          const SizedBox(height: AppSpacing.md - 4),
                          Text(
                            widget.child['names'] ?? 'parent.parent_join_group_screen.yourChild'.tr(),
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primaryDark,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            'common.willJoin'.tr(),
                            style: const TextStyle(
                              fontSize: 16,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: AppSpacing.xl + AppSpacing.sm),

                    Text(
                      'common.groupCode'.tr(),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primaryDark,
                      ),
                    ),

                    const SizedBox(height: AppSpacing.sm),

                    Text(
                      'common.groupCodeMsg'.tr(),
                      style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                    ),

                    const SizedBox(height: AppSpacing.lg),

                    // Group code textfield
                    TextField(
                      controller: groupCodeController,
                      textCapitalization: TextCapitalization.characters,
                      maxLength: 6,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 4,
                      ),
                      decoration: InputDecoration(
                        hintText: 'ABC123',
                        hintStyle: TextStyle(
                          color: Colors.grey[400],
                          letterSpacing: 4,
                        ),
                        prefixIcon: const Icon(
                          Icons.vpn_key_rounded,
                          color: AppColors.primary,
                          size: 28,
                        ),
                        filled: true,
                        fillColor: AppColors.surface,
                        counterText: '',
                        border: OutlineInputBorder(
                          borderRadius: AppRadii.lgAll,
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: AppRadii.lgAll,
                          borderSide: BorderSide(
                            color: Colors.grey.shade300,
                            width: 2,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: AppRadii.lgAll,
                          borderSide: const BorderSide(
                            color: AppColors.primary,
                            width: 2,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: AppSpacing.xl + AppSpacing.sm),

                    // Join button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: isLoading ? null : _joinGroup,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: AppColors.onPrimary,
                          disabledBackgroundColor: Colors.grey[300],
                          padding: const EdgeInsets.symmetric(
                            vertical: AppSpacing.lg - 6,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: AppRadii.lgAll,
                          ),
                          elevation: 4,
                        ),
                        child: isLoading
                            ? const SizedBox(
                                height: 24,
                                width: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.onPrimary,
                                ),
                              )
                            : Text('common.joinGroup'.tr(), style: AppText.button),
                      ),
                    ),

                    const SizedBox(height: AppSpacing.lg),

                    // Info message
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: AppColors.tint(AppColors.success, 0.15),
                        borderRadius: AppRadii.mdAll,
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.info_outline_rounded,
                            color: AppColors.success,
                            size: 24,
                          ),
                          const SizedBox(width: AppSpacing.md - 4),
                          Expanded(
                            child: Text(
                              'common.groupCodeMsg2'.tr(),
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey[800],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
