import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:loringo_app/components/privacy_policy_viewer.dart';
import 'package:loringo_app/theme/app_theme.dart';

/// Checkbox + "View Privacy Policy" link, used both at account signup
/// (general consent) and at child registration (child-data-specific
/// consent) — each call site owns its own `value`/`onChanged` state and
/// supplies the label text appropriate to that moment.
class PolicyConsentCheckbox extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  final String label;

  const PolicyConsentCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Checkbox(
          value: value,
          onChanged: (v) => onChanged(v ?? false),
          activeColor: AppColors.primary,
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: GestureDetector(
              onTap: () => onChanged(!value),
              behavior: HitTestBehavior.opaque,
              child: Wrap(
                children: [
                  Text(
                    label,
                    style: TextStyle(fontSize: 13, color: Colors.grey[800]),
                  ),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: () => showPrivacyPolicyDialog(context),
                    child: Text(
                      'components.policy_consent_checkbox.viewPolicy'.tr(),
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.primary,
                        fontWeight: FontWeight.bold,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
