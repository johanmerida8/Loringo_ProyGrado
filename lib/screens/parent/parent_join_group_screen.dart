import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
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
        const SnackBar(content: Text('Please enter the group code')),
      );
      return;
    }

    setState(() => isLoading = true);

    try {
      // Find group by code
      final groupSnapshot = await FirebaseFirestore.instance
          .collection('teacherGroups')
          .where(
            'groupCode',
            isEqualTo: groupCodeController.text.trim().toUpperCase(),
          )
          .get();

      if (groupSnapshot.docs.isEmpty) {
        throw Exception('Invalid group code');
      }

      final groupDoc = groupSnapshot.docs.first;
      if (groupDoc.data()['archived'] == true) {
        throw Exception('This group is no longer accepting new students');
      }
      final groupId = groupDoc.id;
      final groupName = groupDoc.data()['name'] as String;
      final studentId = widget.child['id'];

      // Update student with groupId
      await FirebaseFirestore.instance
          .collection('students')
          .doc(studentId)
          .update({
            'groupId': groupId,
            'lastUpdate': FieldValue.serverTimestamp(),
          });

      // Create subcollection entry in the group using student UID
      await FirebaseFirestore.instance
          .collection('teacherGroups')
          .doc(groupId)
          .collection('students')
          .doc(studentId)
          .set({
            'studentId': studentId,
            'joinedAt': FieldValue.serverTimestamp(),
          });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✅ ${widget.child['names']} joined the group: $groupName',
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
              content: Text('❌ Error: $e'),
              backgroundColor: AppColors.danger),
        );
      }
    } finally {
      setState(() => isLoading = false);
    }
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.primarySoft(0.1),
                borderRadius: AppRadii.mdAll,
              ),
              child: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: AppColors.primary, size: 18),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          const Text('Join Group', style: AppText.h1),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // NOTE: no Scaffold.appBar — replaced with the inline
      // _buildHeader() below, matching ParentProfileScreen /
      // ParentRegisterChildScreen.
      backgroundColor: AppColors.scaffoldBackground,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(),

                const SizedBox(height: AppSpacing.sm),

                // Info Card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  decoration: BoxDecoration(
                    color: AppColors.tint(AppColors.info, 0.12),
                    borderRadius: AppRadii.lgAll,
                    border: Border.all(
                      color: AppColors.info,
                      width: 2,
                    ),
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
                        widget.child['names'] ?? 'Your child',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primaryDark,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      const Text(
                        'will join the group',
                        style: TextStyle(
                            fontSize: 16, color: AppColors.textPrimary),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: AppSpacing.xl + AppSpacing.sm),

                const Text(
                  'Group Code',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primaryDark,
                  ),
                ),

                const SizedBox(height: AppSpacing.sm),

                Text(
                  'Enter the 6-character code shared by the teacher',
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
                          vertical: AppSpacing.lg - 6),
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
                        : const Text('Join Group', style: AppText.button),
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
                          'The code is provided by the teacher of the group you want to join',
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
    );
  }
}