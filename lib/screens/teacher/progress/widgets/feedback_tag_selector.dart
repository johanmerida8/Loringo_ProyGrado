import 'package:flutter/material.dart';
import 'package:loringo_app/models/feedback_tag.dart';

/// One-tap feedback rating shared by the three teacher review screens.
/// Tapping a tag selects it; tapping the selected tag again clears it.
/// [enabled] is false once the feedback is confirmed / the report sent,
/// matching how those screens already lock the comment field.
class FeedbackTagSelector extends StatelessWidget {
  const FeedbackTagSelector({
    super.key,
    required this.selected,
    required this.onChanged,
    this.enabled = true,
  });

  final String? selected;
  final ValueChanged<String?> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final tag in kFeedbackTags)
          _buildChip(tag),
      ],
    );
  }

  Widget _buildChip(Map<String, dynamic> tag) {
    final key = tag['key'] as String;
    final color = tag['color'] as Color;
    final isSelected = selected == key;
    return ChoiceChip(
      label: Text('${tag['emoji']} ${feedbackTagLabel(key)}'),
      selected: isSelected,
      onSelected: enabled ? (_) => onChanged(isSelected ? null : key) : null,
      showCheckmark: false,
      selectedColor: color.withValues(alpha: 0.18),
      backgroundColor: Colors.white,
      disabledColor:
          isSelected ? color.withValues(alpha: 0.18) : Colors.grey.shade100,
      side: BorderSide(
        color: isSelected ? color : Colors.grey.shade300,
        width: isSelected ? 1.5 : 1,
      ),
      labelStyle: TextStyle(
        fontSize: 13,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
        color: isSelected ? color : Colors.black87,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    );
  }
}
