// import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:flutter/material.dart';
// import 'package:loringo_app/theme/app_theme.dart';

// class StudentGroupTab extends StatefulWidget {
//   final String studentId;
//   final String studentName;
//   final String? studentAvatar;

//   const StudentGroupTab({
//     super.key,
//     required this.studentId,
//     required this.studentName,
//     this.studentAvatar,
//   });

//   @override
//   State<StudentGroupTab> createState() => _StudentGroupTabState();
// }

// class _StudentGroupTabState extends State<StudentGroupTab> {
//   String? groupName;
//   String? teacherName;
//   List<Map<String, dynamic>> classmates = [];
//   bool isLoading = true;

//   @override
//   void initState() {
//     super.initState();
//     _loadGroupInfo();
//   }

//   Future<void> _loadGroupInfo() async {
//     setState(() => isLoading = true);
//     try {
//       final studentDoc = await FirebaseFirestore.instance
//           .collection('students')
//           .doc(widget.studentId)
//           .get();

//       if (studentDoc.exists) {
//         final studentData = studentDoc.data();
//         final groupId = studentData?['groupId'] as String?;

//         if (groupId != null) {
//           // Load group details
//           final groupDoc = await FirebaseFirestore.instance
//               .collection('teacherGroups')
//               .doc(groupId)
//               .get();

//           if (groupDoc.exists) {
//             final groupData = groupDoc.data();
//             setState(() {
//               groupName = groupData?['name'] ?? 'No group assigned';
//               teacherName = groupData?['teacherName'] ?? 'Teacher';
//             });

//             // Load all students in this group
//             final studentsSnapshot = await FirebaseFirestore.instance
//                 .collection('students')
//                 .where('groupId', isEqualTo: groupId)
//                 .get();

//             setState(() {
//               classmates = studentsSnapshot.docs.map((doc) {
//                 final data = doc.data();
//                 return {
//                   'id': doc.id,
//                   'name': data['names'] ?? 'Student',
//                   'avatar': data['avatar'],
//                   'xp': data['xp'] ?? 0,
//                 };
//               }).toList();
//             });
//           }
//         }
//       }
//     } catch (e) {
//       debugPrint('Error loading group info: $e');
//     } finally {
//       setState(() => isLoading = false);
//     }
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Container(
//       decoration: const BoxDecoration(
//         gradient: LinearGradient(
//           colors: [Color(0xFFE8F5E9), Colors.white],
//           begin: Alignment.topCenter,
//           end: Alignment.bottomCenter,
//         ),
//       ),
//       child: SafeArea(
//         child: RefreshIndicator(
//           onRefresh: _loadGroupInfo,
//           child: SingleChildScrollView(
//             physics: const AlwaysScrollableScrollPhysics(),
//             padding: const EdgeInsets.all(AppSpacing.lg),
//             child: Column(
//               crossAxisAlignment: CrossAxisAlignment.center,
//               children: [
//                 const SizedBox(height: AppSpacing.sm),
                
//                 // Student Profile Section
//                 _buildStudentProfile(),
                
//                 const SizedBox(height: AppSpacing.xl),
                
//                 // Group Card
//                 _buildGroupCard(),
                
//                 const SizedBox(height: AppSpacing.xl),
                
//                 // Classmates Section (if available)
//                 if (classmates.length > 1)
//                   _buildClassmatesSection(),
                
//                 const SizedBox(height: AppSpacing.lg),
                
//                 // Motivation Card
//                 _buildMotivationCard(),
                
//                 const SizedBox(height: AppSpacing.xl),
//               ],
//             ),
//           ),
//         ),
//       ),
//     );
//   }

//   Widget _buildStudentProfile() {
//     return Column(
//       children: [
//         Container(
//           decoration: BoxDecoration(
//             shape: BoxShape.circle,
//             boxShadow: [
//               BoxShadow(
//                 color: AppColors.primary.withOpacity(0.3),
//                 blurRadius: 12,
//                 offset: const Offset(0, 4),
//               ),
//             ],
//           ),
//           child: CircleAvatar(
//             radius: 60,
//             backgroundColor: AppColors.primary,
//             backgroundImage: widget.studentAvatar != null
//                 ? AssetImage(widget.studentAvatar!)
//                 : null,
//             child: widget.studentAvatar == null
//                 ? Icon(Icons.person, size: 60, color: Colors.white)
//                 : null,
//           ),
//         ),
//         const SizedBox(height: AppSpacing.md),
//         Text(
//           widget.studentName,
//           style: const TextStyle(
//             fontSize: 28,
//             fontWeight: FontWeight.bold,
//             color: AppColors.primary,
//           ),
//         ),
//         const SizedBox(height: AppSpacing.xs),
//         Container(
//           padding: const EdgeInsets.symmetric(
//             horizontal: AppSpacing.md,
//             vertical: AppSpacing.xs,
//           ),
//           decoration: BoxDecoration(
//             color: AppColors.primary.withOpacity(0.1),
//             borderRadius: BorderRadius.circular(AppRadii.pill),
//           ),
//           child: const Text(
//             'Student',
//             style: TextStyle(
//               fontSize: 14,
//               color: AppColors.primary,
//               fontWeight: FontWeight.w600,
//             ),
//           ),
//         ),
//       ],
//     );
//   }

//   Widget _buildGroupCard() {
//     if (isLoading) {
//       return Container(
//         height: 180,
//         decoration: BoxDecoration(
//           borderRadius: BorderRadius.circular(AppRadii.lg),
//           color: Colors.white,
//         ),
//         child: const Center(child: CircularProgressIndicator()),
//       );
//     }

//     return Container(
//       width: double.infinity,
//       padding: const EdgeInsets.all(AppSpacing.lg),
//       decoration: BoxDecoration(
//         gradient: const LinearGradient(
//           colors: [Color(0xFF4CAF50), Color(0xFF66BB6A)],
//           begin: Alignment.topLeft,
//           end: Alignment.bottomRight,
//         ),
//         borderRadius: BorderRadius.circular(AppRadii.lg),
//         boxShadow: [
//           BoxShadow(
//             color: AppColors.primary.withOpacity(0.3),
//             offset: const Offset(0, 6),
//             blurRadius: 12,
//           ),
//         ],
//       ),
//       child: Column(
//         children: [
//           Container(
//             padding: const EdgeInsets.all(AppSpacing.sm),
//             decoration: BoxDecoration(
//               color: Colors.white.withOpacity(0.2),
//               shape: BoxShape.circle,
//             ),
//             child: const Icon(
//               Icons.groups_rounded,
//               size: 40,
//               color: Colors.white,
//             ),
//           ),
//           const SizedBox(height: AppSpacing.md),
//           const Text(
//             'My Group',
//             style: TextStyle(
//               fontSize: 18,
//               color: Colors.white,
//               fontWeight: FontWeight.w600,
//             ),
//           ),
//           const SizedBox(height: AppSpacing.sm),
//           Text(
//             groupName ?? 'No group assigned',
//             style: const TextStyle(
//               fontSize: 24,
//               color: Colors.white,
//               fontWeight: FontWeight.bold,
//             ),
//             textAlign: TextAlign.center,
//           ),
//           if (teacherName != null) ...[
//             const SizedBox(height: AppSpacing.sm),
//             Text(
//               'Teacher: $teacherName',
//               style: const TextStyle(
//                 fontSize: 14,
//                 color: Colors.white70,
//               ),
//             ),
//           ],
//         ],
//       ),
//     );
//   }

//   Widget _buildClassmatesSection() {
//     // Filter out current student
//     final otherStudents = classmates
//         .where((s) => s['id'] != widget.studentId)
//         .toList();

//     if (otherStudents.isEmpty) return const SizedBox.shrink();

//     return Column(
//       crossAxisAlignment: CrossAxisAlignment.start,
//       children: [
//         Row(
//           children: [
//             Icon(Icons.people_rounded, color: AppColors.primary, size: 24),
//             const SizedBox(width: AppSpacing.sm),
//             const Text(
//               'Classmates',
//               style: TextStyle(
//                 fontSize: 20,
//                 fontWeight: FontWeight.bold,
//                 color: AppColors.textPrimary,
//               ),
//             ),
//             const Spacer(),
//             Text(
//               '${otherStudents.length} ${otherStudents.length == 1 ? 'classmate' : 'classmates'}',
//               style: TextStyle(
//                 fontSize: 14,
//                 color: Colors.grey.shade600,
//               ),
//             ),
//           ],
//         ),
//         const SizedBox(height: AppSpacing.md),
//         GridView.builder(
//           shrinkWrap: true,
//           physics: const NeverScrollableScrollPhysics(),
//           gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
//             crossAxisCount: 2,
//             crossAxisSpacing: AppSpacing.md,
//             mainAxisSpacing: AppSpacing.md,
//             childAspectRatio: 1.2,
//           ),
//           itemCount: otherStudents.length.clamp(0, 6),
//           itemBuilder: (context, index) {
//             final student = otherStudents[index];
//             return _buildClassmateCard(student);
//           },
//         ),
//       ],
//     );
//   }

//   Widget _buildClassmateCard(Map<String, dynamic> student) {
//     return Container(
//       decoration: BoxDecoration(
//         color: Colors.white,
//         borderRadius: BorderRadius.circular(AppRadii.md),
//         boxShadow: [
//           BoxShadow(
//             color: Colors.black.withOpacity(0.05),
//             blurRadius: 8,
//             offset: const Offset(0, 2),
//           ),
//         ],
//       ),
//       child: Column(
//         mainAxisAlignment: MainAxisAlignment.center,
//         children: [
//           CircleAvatar(
//             radius: 30,
//             backgroundColor: AppColors.primary.withOpacity(0.1),
//             backgroundImage: student['avatar'] != null
//                 ? AssetImage(student['avatar']!)
//                 : null,
//             child: student['avatar'] == null
//                 ? Icon(Icons.person, size: 30, color: AppColors.primary)
//                 : null,
//           ),
//           const SizedBox(height: AppSpacing.sm),
//           Text(
//             student['name'] ?? 'Student',
//             style: const TextStyle(
//               fontWeight: FontWeight.w600,
//               fontSize: 14,
//             ),
//             textAlign: TextAlign.center,
//             maxLines: 1,
//             overflow: TextOverflow.ellipsis,
//           ),
//           const SizedBox(height: AppSpacing.xs),
//           Container(
//             padding: const EdgeInsets.symmetric(
//               horizontal: AppSpacing.sm,
//               vertical: AppSpacing.xs,
//             ),
//             decoration: BoxDecoration(
//               color: AppColors.primary.withOpacity(0.1),
//               borderRadius: BorderRadius.circular(AppRadii.sm),
//             ),
//             child: Row(
//               mainAxisSize: MainAxisSize.min,
//               children: [
//                 Icon(Icons.star, size: 12, color: AppColors.warning),
//                 const SizedBox(width: 2),
//                 Text(
//                   '${student['xp']} XP',
//                   style: const TextStyle(
//                     fontSize: 11,
//                     fontWeight: FontWeight.w600,
//                   ),
//                 ),
//               ],
//             ),
//           ),
//         ],
//       ),
//     );
//   }

//   Widget _buildMotivationCard() {
//     return Container(
//       width: double.infinity,
//       padding: const EdgeInsets.all(AppSpacing.lg),
//       decoration: BoxDecoration(
//         gradient: LinearGradient(
//           colors: [Colors.white, Colors.grey.shade50],
//           begin: Alignment.topLeft,
//           end: Alignment.bottomRight,
//         ),
//         borderRadius: BorderRadius.circular(AppRadii.lg),
//         border: Border.all(color: AppColors.primary.withOpacity(0.2), width: 1.5),
//         boxShadow: [
//           BoxShadow(
//             color: Colors.black.withOpacity(0.05),
//             offset: const Offset(0, 4),
//             blurRadius: 12,
//           ),
//         ],
//       ),
//       child: Column(
//         children: [
//           Container(
//             padding: const EdgeInsets.all(AppSpacing.sm),
//             decoration: BoxDecoration(
//               color: const Color(0xFFFE5D26).withOpacity(0.1),
//               shape: BoxShape.circle,
//             ),
//             child: const Icon(
//               Icons.emoji_events_rounded,
//               size: 48,
//               color: Color(0xFFFE5D26),
//             ),
//           ),
//           const SizedBox(height: AppSpacing.md),
//           const Text(
//             'Keep Learning!',
//             style: TextStyle(
//               fontSize: 22,
//               fontWeight: FontWeight.bold,
//               color: Color(0xFFFE5D26),
//             ),
//           ),
//           const SizedBox(height: AppSpacing.sm),
//           Text(
//             'Complete more activities to earn XP and climb the leagues!',
//             textAlign: TextAlign.center,
//             style: TextStyle(
//               fontSize: 14,
//               color: Colors.grey.shade700,
//               height: 1.4,
//             ),
//           ),
//           const SizedBox(height: AppSpacing.md),
//           ElevatedButton.icon(
//             onPressed: () {
//               // Navigate to activities
//               // You can use a callback or navigate directly
//             },
//             icon: const Icon(Icons.play_arrow_rounded, size: 18),
//             label: const Text('Start Learning'),
//             style: ElevatedButton.styleFrom(
//               backgroundColor: AppColors.primary,
//               foregroundColor: Colors.white,
//               padding: const EdgeInsets.symmetric(
//                 horizontal: AppSpacing.lg,
//                 vertical: AppSpacing.sm,
//               ),
//               shape: RoundedRectangleBorder(
//                 borderRadius: BorderRadius.circular(AppRadii.md),
//               ),
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }