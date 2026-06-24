// // admin_approval_content_screen.dart
// import 'package:flutter/material.dart';
// import 'package:loringo_app/components/content_status_badge.dart';
// import 'package:loringo_app/services/database/database.dart';
// import 'package:loringo_app/theme/app_theme.dart';

// class ContentApprovalScreen extends StatefulWidget {
//   const ContentApprovalScreen({super.key});

//   @override
//   State<ContentApprovalScreen> createState() => _ContentApprovalScreenState();
// }

// class _ContentApprovalScreenState extends State<ContentApprovalScreen> {
//   final Database _db = Database();

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       backgroundColor: AppColors.scaffoldBackground,
//       body: StreamBuilder<List<PendingContent>>(
//         stream: _db.getPendingContentStream(),
//         builder: (context, snapshot) {
//           if (snapshot.connectionState == ConnectionState.waiting) {
//             return const Center(
//                 child: CircularProgressIndicator(color: AppColors.primary));
//           }

//           if (!snapshot.hasData || snapshot.data!.isEmpty) {
//             return _EmptyApproval();
//           }

//           final items = snapshot.data!;
//           return CustomScrollView(
//             slivers: [
//               // ── Count banner ──────────────────────────────────────────
//               SliverToBoxAdapter(
//                 child: Container(
//                   margin: const EdgeInsets.fromLTRB(
//                       AppSpacing.md, AppSpacing.md, AppSpacing.md,
//                       AppSpacing.sm),
//                   padding: const EdgeInsets.symmetric(
//                       horizontal: AppSpacing.md,
//                       vertical: AppSpacing.md - 2),
//                   decoration: BoxDecoration(
//                     gradient: AppDecorations.primaryGradient,
//                     borderRadius: BorderRadius.circular(AppRadii.md),
//                     boxShadow: [
//                       BoxShadow(
//                           color: AppColors.primarySoft(0.3),
//                           blurRadius: 12,
//                           offset: const Offset(0, 4))
//                     ],
//                   ),
//                   child: Row(children: [
//                     Container(
//                       padding: const EdgeInsets.all(AppSpacing.sm + 2),
//                       decoration: BoxDecoration(
//                           color: Colors.white.withOpacity(0.2),
//                           borderRadius: BorderRadius.circular(AppRadii.md)),
//                       child: const Icon(Icons.approval_rounded,
//                           color: AppColors.onPrimary, size: 22),
//                     ),
//                     const SizedBox(width: AppSpacing.md),
//                     Column(
//                       crossAxisAlignment: CrossAxisAlignment.start,
//                       children: [
//                         Text(
//                             '${items.length} pending review',
//                             style: const TextStyle(
//                                 color: AppColors.onPrimary,
//                                 fontWeight: FontWeight.bold,
//                                 fontSize: 16)),
//                         const Text('Tap a card to review content',
//                             style: TextStyle(
//                                 color: Colors.white70, fontSize: 12)),
//                       ],
//                     ),
//                   ]),
//                 ),
//               ),

//               // ── Content list ──────────────────────────────────────────
//               SliverPadding(
//                 padding: const EdgeInsets.fromLTRB(
//                     AppSpacing.md, AppSpacing.xs, AppSpacing.md, 100),
//                 sliver: SliverList(
//                   delegate: SliverChildBuilderDelegate(
//                     (_, i) => _ContentCard(
//                       content: items[i],
//                       onApprove: () =>
//                           _approveContent(items[i].contentId, items[i].title),
//                       onReject: () =>
//                           _rejectContent(items[i].contentId, items[i].title),
//                     ),
//                     childCount: items.length,
//                   ),
//                 ),
//               ),
//             ],
//           );
//         },
//       ),
//     );
//   }

//   Future<void> _approveContent(String contentId, String title) async {
//     try {
//       await _db.writeContentApproved(contentId);
//       if (mounted) {
//         ScaffoldMessenger.of(context).showSnackBar(SnackBar(
//           content: Row(children: [
//             const Icon(Icons.check_circle, color: AppColors.onPrimary, size: 18),
//             const SizedBox(width: AppSpacing.sm),
//             Expanded(child: Text('"$title" approved')),
//           ]),
//           backgroundColor: AppColors.primary,
//           behavior: SnackBarBehavior.floating,
//           shape: RoundedRectangleBorder(
//               borderRadius: BorderRadius.circular(AppRadii.md)),
//         ));
//       }
//     } catch (e) {
//       if (mounted) {
//         ScaffoldMessenger.of(context).showSnackBar(SnackBar(
//           content: Text('Error: $e'),
//           backgroundColor: AppColors.danger,
//         ));
//       }
//     }
//   }

//   Future<void> _rejectContent(String contentId, String title) async {
//     final reason = await showDialog<String?>(
//       context: context,
//       builder: (_) => RejectionReasonDialog(title: title),
//     );
//     if (reason == null) return;
//     try {
//       await _db.writeContentRejected(contentId, reason);
//       if (mounted) {
//         ScaffoldMessenger.of(context).showSnackBar(SnackBar(
//           content: Row(children: [
//             const Icon(Icons.cancel, color: AppColors.onPrimary, size: 18),
//             const SizedBox(width: AppSpacing.sm),
//             Expanded(child: Text('"$title" rejected')),
//           ]),
//           backgroundColor: AppColors.danger,
//           behavior: SnackBarBehavior.floating,
//           shape: RoundedRectangleBorder(
//               borderRadius: BorderRadius.circular(AppRadii.md)),
//         ));
//       }
//     } catch (e) {
//       if (mounted) {
//         ScaffoldMessenger.of(context).showSnackBar(SnackBar(
//           content: Text('Error: $e'),
//           backgroundColor: AppColors.danger,
//         ));
//       }
//     }
//   }
// }

// // ── Content card ──────────────────────────────────────────────────────────────

// class _ContentCard extends StatelessWidget {
//   final PendingContent content;
//   final VoidCallback onApprove;
//   final VoidCallback onReject;

//   const _ContentCard({
//     required this.content,
//     required this.onApprove,
//     required this.onReject,
//   });

//   @override
//   Widget build(BuildContext context) {
//     return Container(
//       margin: const EdgeInsets.only(bottom: AppSpacing.md - 2),
//       decoration: BoxDecoration(
//         color: Colors.white,
//         borderRadius: BorderRadius.circular(AppRadii.lg),
//         boxShadow: [
//           BoxShadow(
//               color: Colors.black.withOpacity(0.05),
//               blurRadius: 12,
//               offset: const Offset(0, 4)),
//         ],
//       ),
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           // ── Card header ───────────────────────────────────────────
//           Container(
//             padding: const EdgeInsets.all(AppSpacing.md),
//             decoration: BoxDecoration(
//               color: AppColors.primarySoft(0.04),
//               borderRadius: const BorderRadius.vertical(
//                   top: Radius.circular(AppRadii.lg)),
//               border: Border(
//                   bottom: BorderSide(color: AppColors.primarySoft(0.1))),
//             ),
//             child: Row(children: [
//               Container(
//                 padding: const EdgeInsets.all(AppSpacing.sm + 2),
//                 decoration: BoxDecoration(
//                   color: AppColors.primarySoft(0.1),
//                   borderRadius: BorderRadius.circular(AppRadii.md),
//                 ),
//                 child: const Icon(Icons.article_rounded,
//                     color: AppColors.primary, size: 20),
//               ),
//               const SizedBox(width: AppSpacing.md),
//               Expanded(
//                 child: Column(
//                   crossAxisAlignment: CrossAxisAlignment.start,
//                   children: [
//                     Text(content.title,
//                         style: const TextStyle(
//                             fontSize: 15, fontWeight: FontWeight.bold),
//                         maxLines: 1,
//                         overflow: TextOverflow.ellipsis),
//                     const SizedBox(height: 2),
//                     Text('by ${content.teacherName}',
//                         style: TextStyle(
//                             fontSize: 12, color: Colors.grey[600])),
//                   ],
//                 ),
//               ),
//               ContentStatusBadge(
//                   status: content.status, showIcon: true),
//             ]),
//           ),

//           // ── Body ─────────────────────────────────────────────────
//           Padding(
//             padding: const EdgeInsets.all(AppSpacing.md),
//             child: Column(
//               crossAxisAlignment: CrossAxisAlignment.start,
//               children: [
//                 Text(content.description,
//                     style: TextStyle(
//                         fontSize: 13, color: Colors.grey[700], height: 1.5),
//                     maxLines: 2,
//                     overflow: TextOverflow.ellipsis),

//                 const SizedBox(height: AppSpacing.md - 2),

//                 // Meta row
//                 Row(children: [
//                   _MetaChip(
//                       icon: Icons.cake_rounded,
//                       label: content.ageGroup,
//                       color: Colors.purple),
//                   const SizedBox(width: AppSpacing.sm),
//                   _MetaChip(
//                       icon: Icons.calendar_today_rounded,
//                       label: content.createdAt,
//                       color: AppColors.primary),
//                 ]),

//                 const SizedBox(height: AppSpacing.md),

//                 // Action buttons
//                 Row(children: [
//                   Expanded(
//                     child: OutlinedButton.icon(
//                       onPressed: onReject,
//                       icon: const Icon(Icons.close_rounded, size: 18),
//                       label: const Text('Reject',
//                           style: TextStyle(fontWeight: FontWeight.bold)),
//                       style: OutlinedButton.styleFrom(
//                         foregroundColor: AppColors.danger,
//                         side: BorderSide(
//                             color: AppColors.danger.withOpacity(0.5)),
//                         padding: const EdgeInsets.symmetric(
//                             vertical: AppSpacing.sm + 2),
//                         shape: RoundedRectangleBorder(
//                             borderRadius: BorderRadius.circular(AppRadii.md)),
//                       ),
//                     ),
//                   ),
//                   const SizedBox(width: AppSpacing.md),
//                   Expanded(
//                     child: ElevatedButton.icon(
//                       onPressed: onApprove,
//                       icon: const Icon(Icons.check_rounded, size: 18),
//                       label: const Text('Approve',
//                           style: TextStyle(fontWeight: FontWeight.bold)),
//                       style: ElevatedButton.styleFrom(
//                         backgroundColor: AppColors.primary,
//                         foregroundColor: AppColors.onPrimary,
//                         elevation: 0,
//                         padding: const EdgeInsets.symmetric(
//                             vertical: AppSpacing.sm + 2),
//                         shape: RoundedRectangleBorder(
//                             borderRadius: BorderRadius.circular(AppRadii.md)),
//                       ),
//                     ),
//                   ),
//                 ]),
//               ],
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }

// class _MetaChip extends StatelessWidget {
//   final IconData icon;
//   final String label;
//   final Color color;

//   const _MetaChip(
//       {required this.icon, required this.label, required this.color});

//   @override
//   Widget build(BuildContext context) => Container(
//         padding: const EdgeInsets.symmetric(
//             horizontal: AppSpacing.sm + 2, vertical: AppSpacing.xs + 2),
//         decoration: BoxDecoration(
//           color: color.withOpacity(0.08),
//           borderRadius: BorderRadius.circular(AppRadii.pill),
//         ),
//         child: Row(mainAxisSize: MainAxisSize.min, children: [
//           Icon(icon, size: 13, color: color),
//           const SizedBox(width: AppSpacing.xs + 2),
//           Text(label,
//               style: TextStyle(
//                   fontSize: 11,
//                   color: color,
//                   fontWeight: FontWeight.w600)),
//         ]),
//       );
// }

// // ── Empty state ───────────────────────────────────────────────────────────────

// class _EmptyApproval extends StatelessWidget {
//   @override
//   Widget build(BuildContext context) => Center(
//         child: Padding(
//           padding: const EdgeInsets.all(40),
//           child: Column(
//             mainAxisAlignment: MainAxisAlignment.center,
//             children: [
//               Container(
//                 width: 110,
//                 height: 110,
//                 decoration: BoxDecoration(
//                   gradient: AppDecorations.primaryGradient,
//                   borderRadius: BorderRadius.circular(28),
//                   boxShadow: [
//                     BoxShadow(
//                         color: AppColors.primarySoft(0.4),
//                         blurRadius: 20,
//                         offset: const Offset(0, 8))
//                   ],
//                 ),
//                 child: const Icon(Icons.check_circle_rounded,
//                     size: 52, color: AppColors.onPrimary),
//               ),
//               const SizedBox(height: AppSpacing.lg),
//               const Text('All Caught Up!',
//                   style: TextStyle(
//                       fontSize: 22,
//                       fontWeight: FontWeight.bold,
//                       color: Colors.black87)),
//               const SizedBox(height: AppSpacing.sm),
//               Text('No pending content to review',
//                   textAlign: TextAlign.center,
//                   style: TextStyle(
//                       fontSize: 14,
//                       color: Colors.grey[500],
//                       height: 1.5)),
//             ],
//           ),
//         ),
//       );
// }

// // ── Model ─────────────────────────────────────────────────────────────────────

// class PendingContent {
//   final String contentId;
//   final String title;
//   final String description;
//   final String ageGroup;
//   final String teacherName;
//   final String status;
//   final String createdAt;

//   const PendingContent({
//     required this.contentId,
//     required this.title,
//     required this.description,
//     required this.ageGroup,
//     required this.teacherName,
//     required this.status,
//     required this.createdAt,
//   });
// }

// // ── Rejection dialog ──────────────────────────────────────────────────────────

// class RejectionReasonDialog extends StatefulWidget {
//   final String title;
//   const RejectionReasonDialog({super.key, required this.title});

//   @override
//   State<RejectionReasonDialog> createState() => _RejectionReasonDialogState();
// }

// class _RejectionReasonDialogState extends State<RejectionReasonDialog> {
//   final _ctrl = TextEditingController();

//   @override
//   void dispose() {
//     _ctrl.dispose();
//     super.dispose();
//   }

//   @override
//   Widget build(BuildContext context) {
//     return AlertDialog(
//       shape: RoundedRectangleBorder(
//           borderRadius: BorderRadius.circular(AppRadii.lg)),
//       title: Row(children: [
//         Container(
//           padding: const EdgeInsets.all(AppSpacing.sm),
//           decoration: BoxDecoration(
//               color: AppColors.danger.withOpacity(0.1),
//               borderRadius: BorderRadius.circular(AppRadii.sm)),
//           child: Icon(Icons.block_rounded, color: AppColors.danger, size: 20),
//         ),
//         const SizedBox(width: AppSpacing.md),
//         const Text('Reject Content',
//             style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
//       ]),
//       content: Column(
//         mainAxisSize: MainAxisSize.min,
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           Text('Why are you rejecting "${widget.title}"?',
//               style: const TextStyle(fontSize: 14)),
//           const SizedBox(height: AppSpacing.md),
//           TextField(
//             controller: _ctrl,
//             maxLines: 3,
//             decoration: InputDecoration(
//               hintText: 'Reason (optional)',
//               border: OutlineInputBorder(
//                   borderRadius: BorderRadius.circular(AppRadii.md)),
//               focusedBorder: OutlineInputBorder(
//                   borderRadius: BorderRadius.circular(AppRadii.md),
//                   borderSide: const BorderSide(
//                       color: AppColors.primary, width: 2)),
//             ),
//           ),
//         ],
//       ),
//       actions: [
//         TextButton(
//             onPressed: () => Navigator.pop(context),
//             child: const Text('Cancel',
//                 style: TextStyle(color: AppColors.muted))),
//         ElevatedButton(
//           onPressed: () => Navigator.pop(context, _ctrl.text),
//           style: ElevatedButton.styleFrom(
//               backgroundColor: AppColors.danger,
//               foregroundColor: AppColors.onPrimary,
//               shape: RoundedRectangleBorder(
//                   borderRadius: BorderRadius.circular(AppRadii.sm)),
//               elevation: 0),
//           child:
//               const Text('Reject', style: TextStyle(fontWeight: FontWeight.bold)),
//         ),
//       ],
//     );
//   }
// }