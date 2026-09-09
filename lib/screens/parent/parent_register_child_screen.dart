import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:loringo_app/components/avatar_image.dart';
import 'package:loringo_app/components/avatar_selector.dart';
import 'package:loringo_app/components/policy_consent_checkbox.dart';
import 'package:loringo_app/providers/locale_provider.dart';
import 'package:loringo_app/screens/parent/parent_navigation_screen.dart';
import 'package:loringo_app/services/database/database.dart';
import 'package:loringo_app/services/firebase_refs.dart';
import 'package:loringo_app/theme/app_theme.dart';

class ParentRegisterChildScreen extends StatefulWidget {
  /// True when this screen is being shown as the forced first-run step
  /// (auth_gate.dart's _ParentRouter, for a parent with zero children) —
  /// rendered at the root of the Navigator with nothing to pop back to,
  /// as opposed to being pushed from parent_children_screen.dart's "Add
  /// Child" button (normal back-navigation applies there instead). Swaps
  /// the header's back button for a "Skip for now" action.
  final bool isInitialSetup;

  const ParentRegisterChildScreen({super.key, this.isInitialSetup = false});

  @override
  State<ParentRegisterChildScreen> createState() =>
      _ParentRegisterChildScreenState();
}

class _ParentRegisterChildScreenState extends State<ParentRegisterChildScreen> {
  final childNameController = TextEditingController();
  String? generatedAccessCode;
  bool isRegistered = false;
  String? selectedAvatar;
  bool _isSubmitting = false;
  bool _consentGiven = false;

  @override
  void dispose() {
    childNameController.dispose();
    super.dispose();
  }

  /// Register child and go to parent home
  void _registerChild() async {
    if (childNameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('common.enterChildName'.tr())),
      );
      return;
    }
    if (!_consentGiven) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                'parent.parent_register_child_screen.consentRequired'.tr())),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      // Get parent auth user
      final parentAuthUser = authInstance.currentUser;

      if (parentAuthUser == null) {
        throw Exception('parent.parent_register_child_screen.noAuthUser'.tr());
      }

      // The raw access code is never stored — Database.createStudent hashes
      // it before writing and hands back the plaintext just this once, for
      // the one-time display below.
      final accessCode = await Database(firestore: firestoreInstance).createStudent(
        parentId: parentAuthUser.uid,
        names: childNameController.text.trim(),
        avatar: selectedAvatar ?? kAvatarFallbackAsset,
        childDataConsentAccepted: _consentGiven,
      );

      if (mounted) {
        setState(() {
          generatedAccessCode = accessCode;
          isRegistered = true;
        });
      }
    } catch (e) {
      final message = e.toString().contains('max_children_reached')
          ? 'parent.parent_register_child_screen.maxChildrenReached'
              .tr(namedArgs: {'max': '${Database.maxChildrenPerParent}'})
          : '${'common.errRegisterChild'.tr()}: $e';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
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
        SnackBar(
          content: Text('common.codeCopiedClipboard'.tr()),
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

  /// "Skip for now" — only shown for the forced first-run setup
  /// (isInitialSetup). Persists the choice (Database.skipChildRegistration)
  /// so auth_gate.dart stops forcing this screen on future launches, then
  /// continues into the normal app exactly like a completed registration
  /// would — the parent can still add a child later from the empty-state
  /// "Add Child" button.
  Future<void> _skipForNow() async {
    final uid = authInstance.currentUser?.uid;
    if (uid != null) {
      try {
        await Database(firestore: firestoreInstance).skipChildRegistration(uid);
      } catch (_) {
        // Non-fatal — worst case they're asked again next launch.
      }
    }
    if (mounted) _goToHome();
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
    context.watch<LocaleProvider>();
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
          if (widget.isInitialSetup)
            Expanded(child: Text('common.registerChildSimple'.tr(), style: AppText.h1))
          else ...[
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
            Text('common.registerChildSimple'.tr(), style: AppText.h1),
          ],
          if (widget.isInitialSetup)
            TextButton(
              onPressed: _skipForNow,
              child: Text('parent.parent_register_child_screen.skipForNow'.tr()),
            ),
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

        Text(
          'common.registerChildParent'.tr(),
          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: AppColors.primaryDark,
          ),
        ),

        const SizedBox(height: AppSpacing.sm + 4),

        Text(
          'common.registerChildSub'.tr(),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16, color: Colors.grey[700]),
        ),

        const SizedBox(height: AppSpacing.xl + AppSpacing.sm),

        // Child name textfield
        TextField(
          controller: childNameController,
          decoration: InputDecoration(
            labelText: 'common.childFullname'.tr(),
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
                          child: AvatarImage(
                            avatar: selectedAvatar,
                            fit: BoxFit.cover,
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
                      Text(
                        'common.childAvatar'.tr(),
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.black54,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        selectedAvatar != null
                            ? '${'common.avatarSelected1'.tr()} ✓'
                            : 'common.avatarSelected2'.tr(),
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

        const SizedBox(height: AppSpacing.md),

        PolicyConsentCheckbox(
          value: _consentGiven,
          onChanged: (v) => setState(() => _consentGiven = v),
          label: 'parent.parent_register_child_screen.consentLabel'.tr(),
        ),

        const SizedBox(height: AppSpacing.md),

        // Register button
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: (_isSubmitting || !_consentGiven) ? null : _registerChild,
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
                : Text('common.registerChildSimple'.tr(), style: AppText.button),
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

        Text(
          'common.childRegistered'.tr(),
          style: const TextStyle(
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
              Text(
                'common.studentAccessCode'.tr(),
                textAlign: TextAlign.center,
                style: const TextStyle(
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
                label: Text(
                  'common.copyCode'.tr(),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
              Row(
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    color: AppColors.warning,
                    size: 28,
                  ),
                  const SizedBox(width: AppSpacing.md - 4),
                  Expanded(
                    child: Text(
                      'common.important'.tr(),
                      style: const TextStyle(
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
                'common.importantMsgParent'.tr(),
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
            child: Text('common.continue'.tr(), style: AppText.button),
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
            label: Text(
              'common.registerAnotherChild'.tr(),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ),

        const SizedBox(height: AppSpacing.xl + AppSpacing.lg),
      ],
    );
  }
}