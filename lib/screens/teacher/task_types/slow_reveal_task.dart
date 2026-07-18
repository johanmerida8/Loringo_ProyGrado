import 'package:flutter/material.dart';
import 'package:loringo_app/components/image_dialog.dart';
import 'package:loringo_app/screens/teacher/task_types/task_type_editor.dart';
import 'package:loringo_app/theme/app_theme.dart';

/// Teacher-facing editor for the "Slow Reveal" task type.
///
/// Mechanic (student side, not built here): a single image sits behind
/// an opaque curtain mask. For the first ~3 seconds nothing moves — the
/// curtain holds at 90% coverage, giving the student a moment to process
/// the tiny sliver of shape/color that's visible. After that it uncovers
/// vertically, top to bottom, over the remainder of [revealDurationMs].
/// The image itself is never blurred — it's either covered or not — so
/// what the student sees at any moment is a clean slice of a sharp
/// image, not a degraded version of the whole thing.
///
/// Two response modes, chosen by the teacher:
/// - 'text': student types the English word, free-text.
/// - 'speech': student holds a "Speak now" button and says the word out
///   loud; speech-to-text transcribes it and it's compared the same way
///   as typed text. Push-to-talk (not always-listening) — the student
///   controls exactly when the mic is active, which keeps this
///   consistent with how microphone access is handled elsewhere in the
///   app (see AudioService's sequenced acquisition pattern in
///   reading_task.dart) and avoids an always-on mic during a timed
///   on-screen animation.
///
/// There is deliberately no multiple-choice mode: with only an image as
/// the prompt, showing the answer among 3 options made the task trivial
/// to guess without actually knowing the word. Free production (typed
/// or spoken) is the whole point of this task type.
///
/// If the student hasn't answered correctly by the time the curtain
/// finishes uncovering, that counts as a normal wrong answer (same
/// wrong-answer path as every other task type — see ScreenThirteen).
///
/// Data shape written to Firestore (data field of the task document):
/// {
///   'image': String,              // Cloudinary URL of the image to reveal
///   'responseMode': String,       // 'text' | 'speech'
///   'correctAnswer': String,      // lowercase, trimmed target word
///   'revealDurationMs': int,      // 10000 or 15000
/// }
// class SlowRevealTask extends StatefulWidget {
//   final Color groupColor;
//   final Map<String, dynamic>? existingData;
//   final TaskEditorController controller;
//   final VoidCallback onChanged;

//   const SlowRevealTask({
//     super.key,
//     required this.groupColor,
//     this.existingData,
//     required this.controller,
//     required this.onChanged,
//   });

//   @override
//   State<SlowRevealTask> createState() => _SlowRevealTaskState();
// }

// class _SlowRevealTaskState extends State<SlowRevealTask>
//     with TaskTypeEditorMixin
//     implements TaskTypeEditor {
//   late TextEditingController answerController;

//   // Same picked-image pattern as ImageSelectTask: imageController holds a
//   // display label (or a legacy raw URL typed/loaded before this dialog
//   // existed), pickedImage holds the full SelectImageDialog result map
//   // once the teacher has actually picked something in this session.
//   final TextEditingController imageController = TextEditingController();
//   Map<String, dynamic>? pickedImage;

//   // 'text' or 'speech'.
//   String _responseMode = 'text';

//   // Fixed reveal durations, per the "First Peek / Incremental Slide /
//   // Final Stretch / Hard Cutoff" pacing: a 3s hold at 90% coverage is
//   // built into ScreenThirteen regardless of which duration is picked
//   // here, so the floor moved up to 10s (was 8s) to guarantee at least
//   // ~7s of actual uncovering time after that hold — 8s would have left
//   // only 5s for the whole slide-and-guess phase. 15s ceiling matches
//   // the cited pacing guide's "Hard Cutoff" reference point.
//   static const List<int> _durationOptionsMs = [10000, 15000];
//   int _revealDurationMs = 10000;

//   @override
//   void initState() {
//     super.initState();
//     answerController = TextEditingController();
//     if (widget.existingData != null) {
//       loadData(widget.existingData!);
//     }
//     widget.controller.registerEditor(this);
//   }

//   // ── TaskTypeEditor implementation ─────────────────────────────────────

//   @override
//   String get typeId => 'slow_reveal';

//   @override
//   String get displayName => 'Slow Reveal';

//   @override
//   void loadData(Map<String, dynamic> data) {
//     answerController.text = (data['correctAnswer'] as String? ?? '');
//     imageController.text = (data['image'] as String? ?? '');

//     // Defensive fallback: any task saved under the old 'multiple_choice'
//     // mode (before it was removed) reopens as 'text' rather than
//     // pointing the editor at a UI branch that no longer exists.
//     final storedMode = data['responseMode'] as String?;
//     _responseMode = (storedMode == 'text' || storedMode == 'speech')
//         ? storedMode!
//         : 'text';

//     final storedDuration = data['revealDurationMs'];
//     if (storedDuration is num) {
//       final rounded = storedDuration.round();
//       // Defensive fallback for tasks saved under the earlier 8s/9s
//       // range: snap to the nearest currently-valid option instead of
//       // silently reopening with a duration that no longer has a
//       // matching chip selected.
//       _revealDurationMs = _durationOptionsMs.contains(rounded)
//           ? rounded
//           : (rounded <= 12500 ? 10000 : 15000);
//     }
//   }

//   @override
//   Map<String, dynamic> collectData() {
//     return {
//       'image': pickedImage != null
//           ? (pickedImage!['imageUrl'] as String? ?? '')
//           : imageController.text.trim(),
//       'responseMode': _responseMode,
//       // Normalized here (not on the student side) so every read of this
//       // task's data — student play, teacher preview, future analytics —
//       // sees the same canonical answer without re-implementing the rule.
//       'correctAnswer': answerController.text.trim().toLowerCase(),
//       'revealDurationMs': _revealDurationMs,
//     };
//   }

//   @override
//   String? validate() {
//     final hasImage =
//         pickedImage != null || imageController.text.trim().isNotEmpty;
//     if (!hasImage) return 'Select an image to reveal';
//     if (answerController.text.trim().isEmpty) {
//       return 'Enter the correct answer';
//     }
//     return null;
//   }

//   @override
//   Widget buildEditor(BuildContext context) => build(context);

//   @override
//   void dispose() {
//     answerController.dispose();
//     imageController.dispose();
//     super.dispose();
//   }

//   // ── UI ──────────────────────────────────────────────────────────────

//   @override
//   Widget build(BuildContext context) {
//     final c = widget.groupColor;
//     return Column(
//       crossAxisAlignment: CrossAxisAlignment.start,
//       children: [
//         _buildHeader(c),
//         const SizedBox(height: AppSpacing.md),
//         _buildImagePicker(c),
//         const SizedBox(height: AppSpacing.md),
//         _buildAnswerField(c),
//         const SizedBox(height: AppSpacing.md),
//         _buildResponseModePicker(c),
//         const SizedBox(height: AppSpacing.md),
//         _buildDurationChips(c),
//       ],
//     );
//   }

//   Widget _buildHeader(Color c) {
//     return Container(
//       padding: const EdgeInsets.all(AppSpacing.sm),
//       decoration: BoxDecoration(
//         color: c.withOpacity(0.07),
//         borderRadius: BorderRadius.circular(AppRadii.md),
//       ),
//       child: Row(
//         children: [
//           Icon(Icons.blur_on, color: c, size: 20),
//           const SizedBox(width: AppSpacing.sm),
//           Expanded(
//             child: Text(
//               'The image holds at a small peek for 3s, then a curtain '
//               'uncovers it top to bottom. Students guess what it is '
//               'before it\'s fully revealed.',
//               style: TextStyle(fontSize: 12, color: Colors.grey[700]),
//             ),
//           ),
//         ],
//       ),
//     );
//   }

//   Widget _buildImagePicker(Color c) {
//     final hasImage =
//         pickedImage != null || imageController.text.trim().isNotEmpty;
//     return Column(
//       crossAxisAlignment: CrossAxisAlignment.start,
//       children: [
//         const Text('Image to Reveal',
//             style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
//         const SizedBox(height: AppSpacing.sm),
//         Row(
//           children: [
//             Expanded(
//               child: Container(
//                 height: 120,
//                 decoration: BoxDecoration(
//                   color: Colors.grey[100],
//                   borderRadius: BorderRadius.circular(AppRadii.sm),
//                   border: Border.all(color: AppColors.divider),
//                 ),
//                 child: hasImage
//                     ? ClipRRect(
//                         borderRadius: BorderRadius.circular(AppRadii.sm),
//                         child: Image.network(
//                           pickedImage != null
//                               ? (pickedImage!['displayUrl'] ??
//                                   pickedImage!['imageUrl'])
//                               : imageController.text.trim(),
//                           fit: BoxFit.cover,
//                           errorBuilder: (_, __, ___) =>
//                               const Icon(Icons.broken_image, size: 40),
//                         ),
//                       )
//                     : Center(
//                         child: Text('No image',
//                             style: TextStyle(color: Colors.grey[500])),
//                       ),
//               ),
//             ),
//             const SizedBox(width: AppSpacing.sm),
//             ElevatedButton.icon(
//               onPressed: () async {
//                 final selected = await showDialog(
//                   context: context,
//                   builder: (_) => const SelectImageDialog(singleSelect: true),
//                 );
//                 if (selected != null) {
//                   setState(() {
//                     pickedImage = selected as Map<String, dynamic>;
//                     imageController.text = selected['name'] ?? 'Selected';
//                     widget.onChanged();
//                   });
//                 }
//               },
//               icon: const Icon(Icons.image, size: 18),
//               label: const Text('Select'),
//               style: ElevatedButton.styleFrom(
//                 backgroundColor: Colors.grey[200],
//                 foregroundColor: Colors.black87,
//               ),
//             ),
//           ],
//         ),
//       ],
//     );
//   }

//   Widget _buildAnswerField(Color c) {
//     return Column(
//       crossAxisAlignment: CrossAxisAlignment.start,
//       children: [
//         const Text('Correct Answer',
//             style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
//         const SizedBox(height: AppSpacing.sm),
//         TextFormField(
//           controller: answerController,
//           decoration: _inputDecoration(c, 'e.g. "elephant"'),
//           onChanged: (_) => widget.onChanged(),
//           validator: (v) => v?.trim().isEmpty ?? true ? 'Required' : null,
//         ),
//       ],
//     );
//   }

//   Widget _buildResponseModePicker(Color c) {
//     return Column(
//       crossAxisAlignment: CrossAxisAlignment.start,
//       children: [
//         const Text('Response Mode',
//             style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
//         const SizedBox(height: AppSpacing.sm),
//         Row(
//           children: [
//             Expanded(
//               child: _ModeChip(
//                 label: 'Type the word',
//                 icon: Icons.keyboard,
//                 selected: _responseMode == 'text',
//                 color: c,
//                 onTap: () => setState(() {
//                   _responseMode = 'text';
//                   widget.onChanged();
//                 }),
//               ),
//             ),
//             const SizedBox(width: AppSpacing.sm),
//             Expanded(
//               child: _ModeChip(
//                 label: 'Say the word',
//                 icon: Icons.mic,
//                 selected: _responseMode == 'speech',
//                 color: c,
//                 onTap: () => setState(() {
//                   _responseMode = 'speech';
//                   widget.onChanged();
//                 }),
//               ),
//             ),
//           ],
//         ),
//       ],
//     );
//   }

//   Widget _buildDurationChips(Color c) {
//     return Column(
//       crossAxisAlignment: CrossAxisAlignment.start,
//       children: [
//         const Text('Reveal Duration',
//             style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
//         const SizedBox(height: AppSpacing.sm),
//         Row(
//           children: _durationOptionsMs.map((ms) {
//             final seconds = ms ~/ 1000;
//             final selected = _revealDurationMs == ms;
//             return Padding(
//               padding: const EdgeInsets.only(right: AppSpacing.sm),
//               child: ChoiceChip(
//                 label: Text('${seconds}s'),
//                 selected: selected,
//                 selectedColor: c.withOpacity(0.18),
//                 labelStyle: TextStyle(
//                   color: selected ? c : Colors.black87,
//                   fontWeight: selected ? FontWeight.bold : FontWeight.normal,
//                 ),
//                 side: BorderSide(color: selected ? c : AppColors.divider),
//                 onSelected: (_) => setState(() {
//                   _revealDurationMs = ms;
//                   widget.onChanged();
//                 }),
//               ),
//             );
//           }).toList(),
//         ),
//         const SizedBox(height: 4),
//         Text(
//           'Total time from first peek to fully uncovered (includes a '
//           '3s hold before the curtain starts moving).',
//           style: TextStyle(fontSize: 12, color: Colors.grey[600]),
//         ),
//       ],
//     );
//   }

//   InputDecoration _inputDecoration(Color c, String hint) {
//     return InputDecoration(
//       hintText: hint,
//       border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
//       enabledBorder: OutlineInputBorder(
//         borderRadius: BorderRadius.circular(AppRadii.md),
//         borderSide: BorderSide(color: c.withOpacity(0.3)),
//       ),
//       focusedBorder: OutlineInputBorder(
//         borderRadius: BorderRadius.circular(AppRadii.md),
//         borderSide: BorderSide(color: c, width: 2),
//       ),
//       filled: true,
//       fillColor: Colors.white,
//     );
//   }
// }

// class _ModeChip extends StatelessWidget {
//   final String label;
//   final IconData icon;
//   final bool selected;
//   final Color color;
//   final VoidCallback onTap;

//   const _ModeChip({
//     required this.label,
//     required this.icon,
//     required this.selected,
//     required this.color,
//     required this.onTap,
//   });

//   @override
//   Widget build(BuildContext context) {
//     return InkWell(
//       onTap: onTap,
//       borderRadius: BorderRadius.circular(AppRadii.md),
//       child: Container(
//         padding: const EdgeInsets.symmetric(vertical: 12),
//         decoration: BoxDecoration(
//           color: selected ? color.withOpacity(0.1) : Colors.white,
//           borderRadius: BorderRadius.circular(AppRadii.md),
//           border: Border.all(
//             color: selected ? color : AppColors.divider,
//             width: selected ? 2 : 1,
//           ),
//         ),
//         child: Column(
//           children: [
//             Icon(icon, color: selected ? color : Colors.grey[600], size: 20),
//             const SizedBox(height: 4),
//             Text(
//               label,
//               textAlign: TextAlign.center,
//               style: TextStyle(
//                 fontSize: 12,
//                 fontWeight: selected ? FontWeight.bold : FontWeight.normal,
//                 color: selected ? color : Colors.black87,
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }