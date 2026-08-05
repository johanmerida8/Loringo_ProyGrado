import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:loringo_app/components/avatar_selector.dart';
import 'package:loringo_app/screens/parent/parent_navigation_screen.dart';
import 'package:loringo_app/theme/app_theme.dart';
import 'dart:math';

/// Parent Register Child Screen
/// After parent registers, they must register their child
///
/// COLOR MIGRATION: previously used a standalone warm palette (peach/
/// cream — 0xFFFAEDCA, 0xFFFFCFB3, 0xFFB7E0FF/0xFF4A90E2, 0xFFFE5D26,
/// 0xFFA2CA71, 0xFF387F39, 0xFFF6E96B, 0xFFE67E22) with no tokens of
/// its own. Same migration as ParentJoinGroupScreen — every raw Color
/// below is replaced with the nearest AppColors token, matching the
/// rest of the parent flow (ParentProfileScreen, ParentJoinGroupScreen)
/// rather than keeping this screen's one-off identity.
///
/// HEADER CHANGE: the old `Scaffold(backgroundColor: ...)` with no
/// AppBar at all is replaced with the same inline header pattern
/// ParentProfileScreen uses — a circular back button + large title
/// directly in the body, no solid-color AppBar strip. This screen is
/// only ever pushed (never a tab root), so it needs its own back
/// affordance; ParentProfileScreen's _buildHeader() is the established
/// precedent for how a pushed parent screen should look.
///
/// CHILD LIMIT: added a hard cap of 8 children per parent, mirroring
/// the existing 3-admin cap in Database.createUser(). No legitimate
/// family needs more than 8 student accounts under one parent login —
/// even a large or blended family with multiple children under one
/// guardian's care fits comfortably under this; beyond that, additional
/// "children" are far more likely to be account spam than real use. The
/// limit is enforced with a plain count query before allowing another
/// Firestore write here — same shape as the admin check, no override
/// path.
class ParentRegisterChildScreen extends StatefulWidget {
  const ParentRegisterChildScreen({super.key});

  @override
  State<ParentRegisterChildScreen> createState() =>
      _ParentRegisterChildScreenState();
}

class _ParentRegisterChildScreenState extends State<ParentRegisterChildScreen> {
  static const int _maxChildrenPerParent = 8;

  final childNameController = TextEditingController();
  String? generatedAccessCode;
  bool isRegistered = false;
  String? selectedAvatar;
  bool _isSubmitting = false;

  @override
  void dispose() {
    childNameController.dispose();
    super.dispose();
  }

  /// Generate unique 6-character access code
  String _generateAccessCode() {
    const chars =
        'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // No O, 0, I, 1 to avoid confusion
    final random = Random();
    return List.generate(
      6,
      (index) => chars[random.nextInt(chars.length)],
    ).join();
  }

  /// Register child and go to parent home
  void _registerChild() async {
    if (childNameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your child\'s name')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      // Get parent auth user
      final parentAuthUser = FirebaseAuth.instance.currentUser;

      if (parentAuthUser == null) {
        throw Exception('No authenticated user found');
      }

      final parentUserId = parentAuthUser.uid;

      // FEATURE: enforce the 5-child cap before writing anything. Same
      // pattern as Database.createUser()'s 3-admin check — count first,
      // throw before the write if at/over the limit. Checked here
      // (rather than added as a Database method) since student
      // documents are created directly against Firestore in this
      // screen already, with no Database.createStudent()-style method
      // to hook into.
      final existingChildrenCount = await FirebaseFirestore.instance
          .collection('students')
          .where('parentId', isEqualTo: parentUserId)
          .count()
          .get();
      final currentCount = existingChildrenCount.count ?? 0;
      if (currentCount >= _maxChildrenPerParent) {
        throw Exception(
            'Maximum number of children ($_maxChildrenPerParent) reached');
      }

      // Generate unique access code
      final accessCode = _generateAccessCode();

      // Create student data map
      final newStudentData = {
        'parentId': parentUserId,
        'names': childNameController.text.trim(),
        'accessCode': accessCode,
        'avatar': selectedAvatar ?? 'assets/avatars/parrot.png',
        'state': 1,
        'xp': 0,
        'createdAt': FieldValue.serverTimestamp(),
      };

      // Insert to Firebase. Access code lives only as a field (queried by
      // student_code_screen.dart's `.where('accessCode', ...)` at login) —
      // it's not a stable, safe choice for a document ID (regenerating/
      // rotating a code would mean recreating the whole document), so the
      // student doc gets an auto-generated ID like every other collection.
      await FirebaseFirestore.instance
          .collection('students')
          .add(newStudentData);

      if (mounted) {
        setState(() {
          generatedAccessCode = accessCode;
          isRegistered = true;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error registering child: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  /// Copy access code to clipboard
  void _copyAccessCode() {
    if (generatedAccessCode != null) {
      Clipboard.setData(ClipboardData(text: generatedAccessCode!));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Code copied to clipboard'),
          backgroundColor: AppColors.success,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  /// Navigate to parent home
  void _goToHome() {
    // Replace current screen with ParentHomeScreen
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const ParentNavigationScreen()),
    );
  }

  /// Show avatar selector
  void _showAvatarSelector() {
    showDialog(
      context: context,
      builder: (context) => AvatarSelector(
        currentAvatar: selectedAvatar,
        onAvatarSelected: (avatar) {
          setState(() {
            selectedAvatar = avatar;
          });
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBackground,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.md, AppSpacing.md, AppSpacing.md, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Inline header — see file header for why this
                // replaces the old bare Scaffold with no AppBar at all.
                // Only shown on the form step; the success step has its
                // own celebratory framing and no back action makes
                // sense there (the child is already created).
                if (!isRegistered) _buildHeader(),

                Center(
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                    child: isRegistered
                        ? _buildSuccessView()
                        : _buildRegistrationForm(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
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
          const Text('Register Child', style: AppText.h1),
        ],
      ),
    );
  }

  /// Registration form
  Widget _buildRegistrationForm() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(height: AppSpacing.xl),

        // Logo
        Image.asset(
          'assets/images/loro-llave.png',
          width: 160,
          height: 200,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            return const Icon(
              Icons.school,
              size: 100,
              color: AppColors.primary,
            );
          },
        ),

        const SizedBox(height: AppSpacing.xl + AppSpacing.sm),

        const Text(
          'Register Your Child!',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: AppColors.primaryDark,
          ),
        ),

        const SizedBox(height: AppSpacing.sm + 4),

        Text(
          'To continue, we need your child\'s name',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16, color: Colors.grey[700]),
        ),

        const SizedBox(height: AppSpacing.xl + AppSpacing.sm),

        // Child name textfield
        TextField(
          controller: childNameController,
          decoration: InputDecoration(
            labelText: 'Child\'s full name',
            hintText: 'E.g.: Juan Pérez',
            prefixIcon: const Icon(
              Icons.child_care_rounded,
              color: AppColors.primary,
            ),
            filled: true,
            fillColor: AppColors.surface,
            border: OutlineInputBorder(
              borderRadius: AppRadii.mdAll,
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: AppRadii.mdAll,
              borderSide: BorderSide(color: Colors.grey.shade300, width: 1),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: AppRadii.mdAll,
              borderSide: const BorderSide(color: AppColors.primary, width: 2),
            ),
          ),
        ),

        const SizedBox(height: AppSpacing.lg),

        // Avatar selector button
        GestureDetector(
          onTap: _showAvatarSelector,
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: AppRadii.mdAll,
              border: Border.all(
                color: selectedAvatar != null
                    ? AppColors.info
                    : Colors.grey.shade300,
                width: selectedAvatar != null ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: AppRadii.mdAll,
                  ),
                  child: selectedAvatar != null
                      ? ClipRRect(
                          borderRadius: AppRadii.mdAll,
                          child: Image.asset(
                            selectedAvatar!,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Icon(
                                Icons.face_rounded,
                                color: Colors.grey[400],
                                size: 32,
                              );
                            },
                          ),
                        )
                      : Icon(
                          Icons.face_rounded,
                          color: Colors.grey[400],
                          size: 32,
                        ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Your child\'s avatar',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.black54,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        selectedAvatar != null
                            ? 'Avatar selected ✓'
                            : 'Tap to choose an avatar',
                        style: TextStyle(
                          fontSize: 16,
                          color: selectedAvatar != null
                              ? AppColors.success
                              : Colors.grey[600],
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: Colors.grey[400],
                  size: 20,
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: AppSpacing.xl + AppSpacing.sm),

        // Register button
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _isSubmitting ? null : _registerChild,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.onPrimary,
              disabledBackgroundColor: Colors.grey[300],
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg - 6),
              shape: RoundedRectangleBorder(borderRadius: AppRadii.mdAll),
              elevation: 3,
            ),
            child: _isSubmitting
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.onPrimary,
                    ),
                  )
                : const Text('Register Child', style: AppText.button),
          ),
        ),

        const SizedBox(height: AppSpacing.xl + AppSpacing.md),
      ],
    );
  }

  /// Success view with access code
  Widget _buildSuccessView() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(height: AppSpacing.xl - 2),

        // Success icon
        Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: const BoxDecoration(
            color: AppColors.success,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.check_circle_rounded,
            size: 80,
            color: AppColors.onPrimary,
          ),
        ),

        const SizedBox(height: AppSpacing.xl - 2),

        const Text(
          'Child Registered!',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: AppColors.primaryDark,
          ),
        ),

        const SizedBox(height: AppSpacing.sm + 4),

        Text(
          childNameController.text,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w600,
            color: AppColors.primaryDark,
          ),
        ),

        const SizedBox(height: AppSpacing.xl + AppSpacing.sm),

        // Access code card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            gradient: AppDecorations.primaryGradient,
            borderRadius: AppRadii.lgAll,
            boxShadow: [
              BoxShadow(
                color: AppColors.primarySoft(0.4),
                offset: const Offset(0, 6),
                blurRadius: 12,
              ),
            ],
          ),
          child: Column(
            children: [
              const Icon(Icons.key_rounded,
                  size: 48, color: AppColors.onPrimary),
              const SizedBox(height: AppSpacing.md),
              const Text(
                'Student Access Code',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: AppColors.onPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppSpacing.lg - 4),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.md,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: AppRadii.mdAll,
                ),
                child: Text(
                  generatedAccessCode ?? '',
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 8,
                    color: AppColors.primaryDark,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg - 4),
              ElevatedButton.icon(
                onPressed: _copyAccessCode,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.surface,
                  foregroundColor: AppColors.info,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.sm + 4,
                  ),
                  shape: RoundedRectangleBorder(borderRadius: AppRadii.mdAll),
                ),
                icon: const Icon(Icons.copy_rounded),
                label: const Text(
                  'Copy Code',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: AppSpacing.xl - 2),

        // Important message
        Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: AppColors.tint(AppColors.warning, 0.15),
            borderRadius: AppRadii.lgAll,
            border: Border.all(color: AppColors.warning, width: 2),
          ),
          child: Column(
            children: [
              const Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: AppColors.warning,
                    size: 28,
                  ),
                  SizedBox(width: AppSpacing.md - 4),
                  Expanded(
                    child: Text(
                      'Important!',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.warning,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md - 4),
              Text(
                'Save this code. Your child will need it to log in to the app for the first time.',
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.grey[800],
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: AppSpacing.xl - 2),

        // Continue button
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _goToHome,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.onPrimary,
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg - 6),
              shape: RoundedRectangleBorder(borderRadius: AppRadii.mdAll),
              elevation: 3,
            ),
            child: const Text('Continue', style: AppText.button),
          ),
        ),

        const SizedBox(height: AppSpacing.md - 4),

        // Register another child button
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () {
              // Reset form and go back to registration
              setState(() {
                isRegistered = false;
                generatedAccessCode = null;
                childNameController.clear();
                selectedAvatar = null;
              });
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.success,
              side: const BorderSide(color: AppColors.success, width: 2),
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg - 6),
              shape: RoundedRectangleBorder(borderRadius: AppRadii.mdAll),
            ),
            icon: const Icon(Icons.add),
            label: const Text(
              'Register Another Child',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ),

        const SizedBox(height: AppSpacing.xl + AppSpacing.lg),
      ],
    );
  }
}