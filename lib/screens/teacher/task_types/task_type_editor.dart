// task_type_editor.dart

import 'package:flutter/material.dart';

abstract class TaskTypeEditor {
  String get typeId;
  String get displayName;
  Widget buildEditor(BuildContext context);
  Map<String, dynamic> collectData();
  void loadData(Map<String, dynamic> data);
  String? validate();
  void dispose();
  Future<void> prepareForSubmit(); // ← ADD THIS (declaration only, no body)
}

// Mixin provides the default no-op body so task files don't need to implement it
mixin TaskTypeEditorMixin implements TaskTypeEditor {
  @override
  Future<void> prepareForSubmit() async {}
}

class TaskEditorController {
  final String typeId;
  final String defaultDisplayName;
  TaskTypeEditor? _currentEditor;

  TaskEditorController({
    required this.typeId,
    required this.defaultDisplayName,
  });

  void registerEditor(TaskTypeEditor editor) {
    _currentEditor = editor;
  }

  TaskTypeEditor? get editor => _currentEditor;
  bool get hasEditor => _currentEditor != null;

  Map<String, dynamic> collectData() {
    if (_currentEditor == null) return {};
    return _currentEditor!.collectData();
  }

  String? validate() {
    if (_currentEditor == null) return 'Editor not initialized';
    return _currentEditor!.validate();
  }

  String get displayName {
    return _currentEditor?.displayName ?? defaultDisplayName;
  }

  Future<void> prepareForSubmit() async {
    await _currentEditor?.prepareForSubmit(); // ← now valid, method is on the type
  }
}