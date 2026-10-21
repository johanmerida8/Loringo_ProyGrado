import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:loringo_app/providers/locale_provider.dart';
import 'package:loringo_app/theme/app_theme.dart';

/// "Moderación automática" switch for the image-upload preview, shown right
/// above the upload button. ON by default; switching it OFF asks for
/// confirmation first.
///
/// The switch only REQUESTS skipping Google Vision: the server decides
/// (uploadModeratedImage.ts honors it only if its own setting
/// appSettings/imageModeration allows it for the user's role).
class ModerationSwitch extends StatelessWidget {
  /// The switch state (true = automatic moderation on).
  final ValueNotifier<bool> enabled;

  const ModerationSwitch({super.key, required this.enabled});

  Future<void> _onChanged(BuildContext context, bool wantsOn) async {
    if (wantsOn) {
      enabled.value = true;
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.lg),
        ),
        title: Text('common.moderationDisableTitle'.tr()),
        content: Text('common.moderationDisableBody'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('common.cancel'.tr()),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.warning,
              foregroundColor: AppColors.onPrimary,
              elevation: 0,
            ),
            child: Text('common.moderationDisableConfirm'.tr()),
          ),
        ],
      ),
    );
    if (confirmed == true) enabled.value = false;
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LocaleProvider>();
    return ValueListenableBuilder<bool>(
      valueListenable: enabled,
      builder: (context, isOn, _) => _card(context, isOn),
    );
  }

  Widget _card(BuildContext context, bool on) {
    final color = on ? AppColors.success : AppColors.warning;
    final status = on
        ? 'common.moderationOnStatus'.tr()
        : 'common.moderationOffStatus'.tr();
    return Builder(
      builder: (context) {
        return Container(
          margin: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.md,
            0,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(AppRadii.md),
            border: Border.all(color: color.withValues(alpha: 0.35)),
          ),
          child: Row(
            children: [
              Icon(
                on ? Icons.verified_user_rounded : Icons.shield_outlined,
                color: color,
                size: 22,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'common.moderationTitle'.tr(),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      status,
                      style: TextStyle(fontSize: 12, color: color),
                    ),
                  ],
                ),
              ),
              Switch(
                value: on,
                activeThumbColor: AppColors.success,
                onChanged: (v) => _onChanged(context, v),
              ),
            ],
          ),
        );
      },
    );
  }
}
