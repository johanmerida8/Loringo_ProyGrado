import 'package:flutter/material.dart';
import 'package:loringo_app/screens/teacher/task_types/task_type_editor.dart';
import 'package:loringo_app/theme/app_theme.dart';

class RepeatAfterMeTask extends StatefulWidget {
  final Color groupColor;
  final Map<String, dynamic>? existingData;
  final TaskEditorController controller;
  final VoidCallback onChanged;

  const RepeatAfterMeTask({
    super.key,
    required this.groupColor,
    this.existingData,
    required this.controller,
    required this.onChanged,
  });

  @override
  State<RepeatAfterMeTask> createState() => _RepeatAfterMeTaskState();
}

class _RepeatAfterMeTaskState extends State<RepeatAfterMeTask> with TaskTypeEditorMixin implements TaskTypeEditor {
  late TextEditingController phraseController;
  late TextEditingController hintController;
  
  @override
  void initState() {
    super.initState();
    phraseController = TextEditingController();
    hintController = TextEditingController();
    
    if (widget.existingData != null) {
      loadData(widget.existingData!);
    }
    
    widget.controller.registerEditor(this);
  }

  // TaskTypeEditor implementation
  @override
  String get typeId => 'repeat_after_me';
  
  @override
  String get displayName => 'Repeat After Me';
  
  @override
  Widget buildEditor(BuildContext context) {
    return build(context);
  }

  @override
  Widget build(BuildContext context) {
    return _buildEditor();
  }

  @override
  void loadData(Map<String, dynamic> data) {
    phraseController.text = data['phrase'] ?? '';
    hintController.text = data['hint'] ?? '';
  }

  @override
  Map<String, dynamic> collectData() {
    return {
      'phrase': phraseController.text.trim(),
      'hint': hintController.text.trim(),
    };
  }

  @override
  String? validate() {
    if (phraseController.text.trim().isEmpty) {
      return 'Please enter a phrase for students to repeat';
    }
    return null;
  }

  @override
  void dispose() {
    phraseController.dispose();
    hintController.dispose();
    super.dispose();
  }

  Widget _buildEditor() {
    final c = widget.groupColor;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Info Banner ────────────────────────────────────────────────
        _buildInfoBanner(c),
        const SizedBox(height: AppSpacing.md),
        
        // ── Phrase Field ──────────────────────────────────────────────
        _buildPhraseField(c),
        const SizedBox(height: AppSpacing.md),
        
        // ── Hint Field ────────────────────────────────────────────────
        _buildHintField(c),
        
        // ── Preview Section ───────────────────────────────────────────
        // const SizedBox(height: AppSpacing.md),
        // _buildPreviewSection(c),
      ],
    );
  }

  Widget _buildInfoBanner(Color c) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: c.withOpacity(0.07),
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: c.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Icon(Icons.record_voice_over, color: c, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Students listen to the phrase and repeat it out loud. They must repeat it correctly to continue.',
              style: TextStyle(fontSize: 12, color: Colors.grey[700]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhraseField(Color c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'English Phrase',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        TextFormField(
          controller: phraseController,
          decoration: InputDecoration(
            hintText: 'Enter the phrase students should repeat',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
            filled: true,
            fillColor: Colors.white,
          ),
          maxLines: 3,
          onChanged: (_) => widget.onChanged(),
          validator: (v) => v?.trim().isEmpty ?? true ? 'Required' : null,
        ),
        const SizedBox(height: 8),
        Text(
          '💡 This phrase will be spoken aloud by the voice assistant. Students must repeat it correctly.',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
        ),
      ],
    );
  }

  Widget _buildHintField(Color c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Hint (Optional)',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: AppSpacing.xs),
        TextFormField(
          controller: hintController,
          decoration: InputDecoration(
            hintText: 'e.g. "Focus on the pronunciation of \'th\' in \'three\'"',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
            filled: true,
            fillColor: Colors.white,
          ),
          maxLines: 2,
          onChanged: (_) => widget.onChanged(),
        ),
        const SizedBox(height: 8),
        Text(
          '💡 Optional instruction shown to students before the task. Use it to guide their pronunciation.',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
        ),
      ],
    );
  }

  // Widget _buildPreviewSection(Color c) {
  //   final phrase = phraseController.text.trim().isNotEmpty 
  //       ? phraseController.text.trim() 
  //       : 'I am American, but I speak Italian';
    
  //   final hint = hintController.text.trim().isNotEmpty 
  //       ? hintController.text.trim() 
  //       : null;

  //   return Container(
  //     padding: const EdgeInsets.all(AppSpacing.md),
  //     decoration: BoxDecoration(
  //       color: Colors.grey.shade50,
  //       borderRadius: BorderRadius.circular(AppRadii.md),
  //       border: Border.all(color: Colors.grey.shade200),
  //     ),
  //     child: Column(
  //       crossAxisAlignment: CrossAxisAlignment.start,
  //       children: [
  //         Row(
  //           children: [
  //             Icon(Icons.preview, color: c, size: 18),
  //             const SizedBox(width: AppSpacing.xs),
  //             Text(
  //               'Preview (Student View)',
  //               style: TextStyle(
  //                 fontSize: 13,
  //                 fontWeight: FontWeight.bold,
  //                 color: c,
  //               ),
  //             ),
  //           ],
  //         ),
  //         const SizedBox(height: AppSpacing.sm),
  //         Container(
  //           padding: const EdgeInsets.all(AppSpacing.md),
  //           decoration: BoxDecoration(
  //             color: Colors.white,
  //             borderRadius: BorderRadius.circular(AppRadii.md),
  //             border: Border.all(color: Colors.grey.shade300),
  //           ),
  //           child: Column(
  //             crossAxisAlignment: CrossAxisAlignment.start,
  //             children: [
  //               // Header
  //               Row(
  //                 children: [
  //                   Icon(Icons.volume_up, color: c, size: 20),
  //                   const SizedBox(width: 8),
  //                   const Text(
  //                     'Listen and Repeat',
  //                     style: TextStyle(
  //                       fontSize: 14,
  //                       fontWeight: FontWeight.bold,
  //                     ),
  //                   ),
  //                 ],
  //               ),
  //               const SizedBox(height: 12),
                
  //               // Phrase to repeat
  //               Container(
  //                 padding: const EdgeInsets.all(12),
  //                 decoration: BoxDecoration(
  //                   color: c.withOpacity(0.05),
  //                   borderRadius: BorderRadius.circular(8),
  //                   border: Border.all(color: c.withOpacity(0.2)),
  //                 ),
  //                 child: Column(
  //                   children: [
  //                     const Text(
  //                       'Repeat this phrase:',
  //                       style: TextStyle(
  //                         fontSize: 12,
  //                         color: Colors.grey,
  //                       ),
  //                     ),
  //                     const SizedBox(height: 8),
  //                     Text(
  //                       phrase,
  //                       style: TextStyle(
  //                         fontSize: 18,
  //                         fontWeight: FontWeight.w500,
  //                         color: Colors.black87,
  //                       ),
  //                       textAlign: TextAlign.center,
  //                     ),
  //                   ],
  //                 ),
  //               ),
                
  //               if (hint != null) ...[
  //                 const SizedBox(height: 12),
  //                 Container(
  //                   padding: const EdgeInsets.all(10),
  //                   decoration: BoxDecoration(
  //                     color: Colors.blue.shade50,
  //                     borderRadius: BorderRadius.circular(8),
  //                     border: Border.all(color: Colors.blue.shade200),
  //                   ),
  //                   child: Row(
  //                     children: [
  //                       Icon(Icons.lightbulb_outline, color: Colors.blue.shade700, size: 16),
  //                       const SizedBox(width: 8),
  //                       Expanded(
  //                         child: Text(
  //                           '💡 $hint',
  //                           style: TextStyle(
  //                             fontSize: 13,
  //                             color: Colors.blue.shade700,
  //                             height: 1.3,
  //                           ),
  //                         ),
  //                       ),
  //                     ],
  //                   ),
  //                 ),
  //               ],
                
  //               const SizedBox(height: 16),
                
  //               // Action buttons - NO SKIP, just Record
  //               Row(
  //                 mainAxisAlignment: MainAxisAlignment.center,
  //                 children: [
  //                   ElevatedButton.icon(
  //                     onPressed: null,
  //                     icon: const Icon(Icons.mic, size: 18),
  //                     label: const Text(
  //                       'Tap to Record',
  //                       style: TextStyle(fontSize: 14),
  //                     ),
  //                     style: ElevatedButton.styleFrom(
  //                       backgroundColor: c,
  //                       foregroundColor: Colors.white,
  //                       padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
  //                       shape: RoundedRectangleBorder(
  //                         borderRadius: BorderRadius.circular(12),
  //                       ),
  //                     ),
  //                   ),
  //                 ],
  //               ),
  //               const SizedBox(height: 8),
  //               Center(
  //                 child: Text(
  //                   'Press record and repeat the phrase aloud',
  //                   style: TextStyle(
  //                     fontSize: 11,
  //                     color: Colors.grey.shade500,
  //                   ),
  //                 ),
  //               ),
  //             ],
  //           ),
  //         ),
  //       ],
  //     ),
  //   );
  // }
}