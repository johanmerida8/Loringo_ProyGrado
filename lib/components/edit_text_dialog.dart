import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:loringo_app/theme/app_theme.dart';

/// Shows a dialog with a single text field to edit a value (e.g. display
/// name). Returns the new value if saved, or null if cancelled.
Future<String?> showEditTextDialog(
  BuildContext context, {
  required String title,
  required String initialValue,
  required Future<void> Function(String newValue) onSave,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _EditTextDialog(
      title: title,
      initialValue: initialValue,
      onSave: onSave,
    ),
  );
}

class _EditTextDialog extends StatefulWidget {
  final String title;
  final String initialValue;
  final Future<void> Function(String newValue) onSave;

  const _EditTextDialog({
    required this.title,
    required this.initialValue,
    required this.onSave,
  });

  @override
  State<_EditTextDialog> createState() => _EditTextDialogState();
}

class _EditTextDialogState extends State<_EditTextDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialValue);
  String? _error;
  bool _saving = false;

  Future<void> _handleSave() async {
    final value = _controller.text.trim();
    if (value.isEmpty) {
      setState(() => _error = 'common.nameValidation'.tr());
      return;
    }

    if (value == widget.initialValue.trim()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('common.noChangesMade'.tr())),
      );
      Navigator.pop(context);
      return;
    }

    setState(() {
      _error = null;
      _saving = true;
    });

    try {
      await widget.onSave(value);
      if (mounted) Navigator.pop(context, value);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'common.error'.tr();
        });
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      title: Text(widget.title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      content: TextField(
        controller: _controller,
        autofocus: true,
        enabled: !_saving,
        decoration: InputDecoration(
          errorText: _error,
          border: const OutlineInputBorder(),
        ),
        onSubmitted: (_) => _handleSave(),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
          child: Text('common.cancel'.tr()),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _handleSave,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.onPrimary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
            elevation: 0,
          ),
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : Text('common.save'.tr()),
        ),
      ],
    );
  }
}
