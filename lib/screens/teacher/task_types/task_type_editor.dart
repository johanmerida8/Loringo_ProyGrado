import 'package:flutter/material.dart';

/// Abstract interface that all task type states must implement
abstract class TaskTypeEditor {
  String get typeId;
  String get displayName;
  // String get defaultQuestion;
  Widget buildEditor(BuildContext context);
  Map<String, dynamic> collectData();
  void loadData(Map<String, dynamic> data);
  String? validate();
  void dispose();
}

/// Controller that holds the current editor state
class TaskEditorController {
  final String typeId;
  final String defaultDisplayName;
  TaskTypeEditor? _currentEditor;
  
  /// Constructor - requires typeId and default display name
  TaskEditorController({
    required this.typeId,
    required this.defaultDisplayName,
  });
  
  /// Register an editor (called by the task widget's state)
  void registerEditor(TaskTypeEditor editor) {
    _currentEditor = editor;
  }
  
  /// Get the current editor (if registered)
  TaskTypeEditor? get editor => _currentEditor;
  
  /// Check if an editor has been registered
  bool get hasEditor => _currentEditor != null;
  
  /// Collect data from the registered editor
  Map<String, dynamic> collectData() {
    if (_currentEditor == null) return {};
    return _currentEditor!.collectData();
  }
  
  /// Validate the registered editor
  String? validate() {
    if (_currentEditor == null) return 'Editor not initialized';
    return _currentEditor!.validate();
  }
  
  /// Get default question from registered editor
  // String get defaultQuestion {
  //   return _currentEditor?.defaultQuestion ?? '';
  // }
  
  /// Get display name (from registered editor or default)
  String get displayName {
    return _currentEditor?.displayName ?? defaultDisplayName;
  }
  
}