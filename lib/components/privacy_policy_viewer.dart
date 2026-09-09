import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:loringo_app/theme/app_theme.dart';
import 'package:loringo_app/utils/privacy_policy.dart';

/// Opens a scrollable dialog showing the privacy policy text in the
/// current locale (see loadPrivacyPolicyText). Used by
/// PolicyConsentCheckbox's "View Privacy Policy" link.
Future<void> showPrivacyPolicyDialog(BuildContext context) async {
  final locale = context.locale;
  await showDialog(
    context: context,
    builder: (context) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: AppRadii.lgAll),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 600),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'components.privacy_policy_viewer.title'.tr(),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primaryDark,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                    color: AppColors.muted,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Flexible(
                child: FutureBuilder<String>(
                  future: loadPrivacyPolicyText(locale),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    return SingleChildScrollView(
                      child: Text(
                        snapshot.data!,
                        style: const TextStyle(fontSize: 13, height: 1.5),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.onPrimary,
                    shape: RoundedRectangleBorder(borderRadius: AppRadii.mdAll),
                  ),
                  child: Text('common.close'.tr()),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
