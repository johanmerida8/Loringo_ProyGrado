// // teacher_profile_screen.dart
// //
// // Self-contained profile screen for the Teacher role.
// // Style mirrors parent_profile_screen.dart exactly:
// //   • Mint scaffold (#EFF6EE)
// //   • Inline back-button header (no AppBar)
// //   • Gradient header card
// //   • White menu cards using _SectionCard / _InfoRow
// //   • Notifications row (teachers receive XP/league reports)
// //   • Security row (biometrics + change password)
// //   • Personal data sub-screen
// //   • Logout

// import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:firebase_auth/firebase_auth.dart';
// import 'package:flutter/material.dart';
// import 'package:loringo_app/screens/initials/reset_in_app_screen.dart';
// import 'package:loringo_app/services/auth/auth_gate.dart';
// import 'package:loringo_app/services/notifications/notification_helper.dart';
// import 'package:loringo_app/services/notifications/notification_permission_service.dart';
// import 'package:loringo_app/theme/app_theme.dart';
// import 'package:local_auth/local_auth.dart';
// import 'package:loringo_app/services/auth/biometric_service.dart';

// class TeacherProfileScreen extends StatefulWidget {
//   const TeacherProfileScreen({super.key});

//   @override
//   State<TeacherProfileScreen> createState() => _TeacherProfileScreenState();
// }

// class _TeacherProfileScreenState extends State<TeacherProfileScreen>
//     with WidgetsBindingObserver {

//   // ── User data ─────────────────────────────────────────────────────────────
//   String _name  = '';
//   String _email = '';
//   bool   _loadingUser = true;

//   // ── Biometrics ────────────────────────────────────────────────────────────
//   bool   _bioSupported = false;
//   bool   _bioEnabled   = false;
//   bool   _bioLoading   = true;
//   List<BiometricType> _availableBio = [];
//   String _bioTypeName  = 'Biometrics';

//   // ── Notifications ─────────────────────────────────────────────────────────
//   bool _notificationsEnabled   = false;
//   bool _loadingNotifications   = true;

//   @override
//   void initState() {
//     super.initState();
//     WidgetsBinding.instance.addObserver(this);
//     _loadUser();
//     _initBiometrics();
//     _loadNotificationStatus();
//   }

//   @override
//   void dispose() {
//     WidgetsBinding.instance.removeObserver(this);
//     super.dispose();
//   }

//   @override
//   void didChangeAppLifecycleState(AppLifecycleState state) {
//     if (state == AppLifecycleState.resumed) _loadNotificationStatus();
//   }

//   // ── Data loaders ──────────────────────────────────────────────────────────

//   Future<void> _loadUser() async {
//     final uid = FirebaseAuth.instance.currentUser?.uid;
//     if (uid == null) return;
//     final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
//     if (!mounted) return;
//     setState(() {
//       _name        = (doc.data()?['name']  as String?) ?? '';
//       _email       = (doc.data()?['email'] as String?) ??
//                      FirebaseAuth.instance.currentUser?.email ?? '';
//       _loadingUser = false;
//     });
//   }

//   Future<void> _initBiometrics() async {
//     final uid = FirebaseAuth.instance.currentUser?.uid;
//     if (uid == null) { setState(() => _bioLoading = false); return; }
//     try {
//       final supported = await BiometricService.isDeviceSupported();
//       final canCheck  = await BiometricService.canCheckBiometrics();
//       final available = await BiometricService.getAvailableBiometrics();
//       final enabled   = await BiometricService.isBiometricEnabled(uid);
//       if (!mounted) return;
//       setState(() {
//         _bioSupported   = supported && canCheck;
//         _availableBio   = available;
//         _bioTypeName    = BiometricService.getBiometricTypeName(available);
//         _bioEnabled     = enabled;
//         _bioLoading     = false;
//       });
//     } catch (_) {
//       if (mounted) setState(() => _bioLoading = false);
//     }
//   }

//   Future<void> _loadNotificationStatus() async {
//     final granted = await NotificationPermissionService.isPermissionGranted();
//     if (mounted) {
//       setState(() {
//         _notificationsEnabled  = granted;
//         _loadingNotifications  = false;
//       });
//     }
//   }

//   // ── Actions ───────────────────────────────────────────────────────────────

//   Future<void> _toggleBiometric(bool value) async {
//     final uid = FirebaseAuth.instance.currentUser?.uid;
//     if (uid == null) return;
//     if (value) {
//       final ok = await BiometricService.authenticate(
//           reason: 'Verify your identity to enable biometric login');
//       if (ok) {
//         await BiometricService.setBiometricEnabled(userId: uid, enabled: true);
//         setState(() => _bioEnabled = true);
//         _snack('Biometric login enabled');
//       } else {
//         _snack('Authentication failed', color: AppColors.danger);
//       }
//     } else {
//       await BiometricService.setBiometricEnabled(userId: uid, enabled: false);
//       setState(() => _bioEnabled = false);
//     }
//   }

//   Future<void> _toggleNotifications(bool value) async {
//     final uid = FirebaseAuth.instance.currentUser?.uid;
//     if (value) {
//       final granted = await NotificationHelper.requestEnable(
//           context: context, userId: uid);
//       setState(() => _notificationsEnabled = granted);
//       if (granted) _snack('Notifications enabled');
//     } else {
//       await NotificationHelper.requestDisable(context: context);
//       await _loadNotificationStatus();
//     }
//   }

//   void _showLogoutConfirmation() {
//     showDialog(
//       context: context,
//       builder: (_) => AlertDialog(
//         shape: RoundedRectangleBorder(
//             borderRadius: BorderRadius.circular(AppRadii.lg)),
//         title: const Text('Log Out'),
//         content: const Text('Are you sure you want to log out?'),
//         actions: [
//           TextButton(
//               onPressed: () => Navigator.pop(context),
//               child: const Text('Cancel',
//                   style: TextStyle(color: AppColors.muted))),
//           TextButton(
//             onPressed: () async {
//               Navigator.pop(context);
//               await FirebaseAuth.instance.signOut();
//               if (mounted) {
//                 Navigator.of(context).pushAndRemoveUntil(
//                   MaterialPageRoute(builder: (_) => const AuthGate()),
//                   (r) => false,
//                 );
//               }
//             },
//             style: TextButton.styleFrom(foregroundColor: AppColors.warning),
//             child: const Text('Log Out',
//                 style: TextStyle(fontWeight: FontWeight.bold)),
//           ),
//         ],
//       ),
//     );
//   }

//   void _navigateToPersonalData() {
//     Navigator.push(context, MaterialPageRoute(
//       builder: (_) => _PersonalDataScreen(name: _name, email: _email),
//     ));
//   }

//   void _navigateToSecurity() {
//     Navigator.push(context, MaterialPageRoute(
//       builder: (_) => _SecurityScreen(
//         bioLoading:   _bioLoading,
//         bioSupported: _bioSupported,
//         bioTypeName:  _bioTypeName,
//         bioEnabled:   _bioEnabled,
//         onToggle:     _toggleBiometric,
//       ),
//     ));
//   }

//   void _snack(String msg, {Color color = AppColors.primary}) {
//     if (!mounted) return;
//     ScaffoldMessenger.of(context).showSnackBar(SnackBar(
//       content: Text(msg), backgroundColor: color,
//       behavior: SnackBarBehavior.floating,
//       shape: RoundedRectangleBorder(
//           borderRadius: BorderRadius.circular(AppRadii.md)),
//     ));
//   }

//   // ── Build ─────────────────────────────────────────────────────────────────

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       backgroundColor: const Color(0xFFEFF6EE),
//       body: SafeArea(
//         child: _loadingUser
//             ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
//             : SingleChildScrollView(
//                 child: Column(
//                   children: [
//                     // Inline header
//                     Padding(
//                       padding: const EdgeInsets.fromLTRB(
//                           AppSpacing.md, AppSpacing.md, AppSpacing.md, 0),
//                       child: Row(children: [
//                         GestureDetector(
//                           onTap: () => Navigator.pop(context),
//                           child: Container(
//                             padding: const EdgeInsets.all(AppSpacing.sm),
//                             decoration: BoxDecoration(
//                               color: AppColors.primarySoft(0.1),
//                               borderRadius: BorderRadius.circular(AppRadii.md),
//                             ),
//                             child: const Icon(Icons.arrow_back_ios_new_rounded,
//                                 color: AppColors.primary, size: 18),
//                           ),
//                         ),
//                         const SizedBox(width: AppSpacing.md),
//                         const Text('My Profile', style: AppText.h1),
//                       ]),
//                     ),

//                     const SizedBox(height: AppSpacing.md),

//                     // Gradient header card
//                     _ProfileHeader(
//                         name: _name, role: 'Teacher',
//                         icon: Icons.school_rounded),

//                     const SizedBox(height: AppSpacing.md),

//                     // Menu
//                     _MenuCard(items: [
//                       _MenuItem(
//                         icon: Icons.person_outline_rounded,
//                         title: 'Personal Data',
//                         subtitle: 'View and manage your information',
//                         onTap: _navigateToPersonalData,
//                       ),
//                       _MenuItem(
//                         icon: Icons.security_rounded,
//                         title: 'Security',
//                         subtitle: 'Biometric & password settings',
//                         onTap: _navigateToSecurity,
//                       ),
//                       _MenuItem(
//                         icon: Icons.notifications_active_rounded,
//                         title: 'Notifications',
//                         subtitle: 'Get notified about class activity',
//                         onTap: () =>
//                             _toggleNotifications(!_notificationsEnabled),
//                         trailing: _loadingNotifications
//                             ? const SizedBox(
//                                 width: 20, height: 20,
//                                 child: CircularProgressIndicator(
//                                     strokeWidth: 2,
//                                     color: AppColors.primary))
//                             : Switch(
//                                 value: _notificationsEnabled,
//                                 onChanged: _toggleNotifications,
//                                 activeColor: AppColors.primary,
//                               ),
//                       ),
//                       _MenuItem(
//                         icon: Icons.logout_rounded,
//                         title: 'Log Out',
//                         subtitle: 'Sign out from your account',
//                         onTap: _showLogoutConfirmation,
//                       ),
//                     ]),

//                     const SizedBox(height: AppSpacing.xl),
//                   ],
//                 ),
//               ),
//       ),
//     );
//   }
// }

// // ─────────────────────────────────────────────────────────────────────────────
// // AdminProfileScreen
// // Same style, no notifications row, no delete-account.
// // ─────────────────────────────────────────────────────────────────────────────

// class AdminProfileScreen extends StatefulWidget {
//   const AdminProfileScreen({super.key});

//   @override
//   State<AdminProfileScreen> createState() => _AdminProfileScreenState();
// }

// class _AdminProfileScreenState extends State<AdminProfileScreen> {
//   String _name  = '';
//   String _email = '';
//   bool   _loadingUser = true;

//   bool   _bioSupported = false;
//   bool   _bioEnabled   = false;
//   bool   _bioLoading   = true;
//   List<BiometricType> _availableBio = [];
//   String _bioTypeName  = 'Biometrics';

//   @override
//   void initState() {
//     super.initState();
//     _loadUser();
//     _initBiometrics();
//   }

//   Future<void> _loadUser() async {
//     final uid = FirebaseAuth.instance.currentUser?.uid;
//     if (uid == null) return;
//     final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
//     if (!mounted) return;
//     setState(() {
//       _name        = (doc.data()?['name']  as String?) ?? '';
//       _email       = (doc.data()?['email'] as String?) ??
//                      FirebaseAuth.instance.currentUser?.email ?? '';
//       _loadingUser = false;
//     });
//   }

//   Future<void> _initBiometrics() async {
//     final uid = FirebaseAuth.instance.currentUser?.uid;
//     if (uid == null) { setState(() => _bioLoading = false); return; }
//     try {
//       final supported = await BiometricService.isDeviceSupported();
//       final canCheck  = await BiometricService.canCheckBiometrics();
//       final available = await BiometricService.getAvailableBiometrics();
//       final enabled   = await BiometricService.isBiometricEnabled(uid);
//       if (!mounted) return;
//       setState(() {
//         _bioSupported = supported && canCheck;
//         _availableBio = available;
//         _bioTypeName  = BiometricService.getBiometricTypeName(available);
//         _bioEnabled   = enabled;
//         _bioLoading   = false;
//       });
//     } catch (_) {
//       if (mounted) setState(() => _bioLoading = false);
//     }
//   }

//   Future<void> _toggleBiometric(bool value) async {
//     final uid = FirebaseAuth.instance.currentUser?.uid;
//     if (uid == null) return;
//     if (value) {
//       final ok = await BiometricService.authenticate(
//           reason: 'Verify your identity to enable biometric login');
//       if (ok) {
//         await BiometricService.setBiometricEnabled(userId: uid, enabled: true);
//         setState(() => _bioEnabled = true);
//         _snack('Biometric login enabled');
//       } else {
//         _snack('Authentication failed', color: AppColors.danger);
//       }
//     } else {
//       await BiometricService.setBiometricEnabled(userId: uid, enabled: false);
//       setState(() => _bioEnabled = false);
//     }
//   }

//   void _showLogoutConfirmation() {
//     showDialog(
//       context: context,
//       builder: (_) => AlertDialog(
//         shape: RoundedRectangleBorder(
//             borderRadius: BorderRadius.circular(AppRadii.lg)),
//         title: const Text('Log Out'),
//         content: const Text('Are you sure you want to log out?'),
//         actions: [
//           TextButton(
//               onPressed: () => Navigator.pop(context),
//               child: const Text('Cancel',
//                   style: TextStyle(color: AppColors.muted))),
//           TextButton(
//             onPressed: () async {
//               Navigator.pop(context);
//               await FirebaseAuth.instance.signOut();
//               if (mounted) {
//                 Navigator.of(context).pushAndRemoveUntil(
//                   MaterialPageRoute(builder: (_) => const AuthGate()),
//                   (r) => false,
//                 );
//               }
//             },
//             style: TextButton.styleFrom(foregroundColor: AppColors.warning),
//             child: const Text('Log Out',
//                 style: TextStyle(fontWeight: FontWeight.bold)),
//           ),
//         ],
//       ),
//     );
//   }

//   void _navigateToPersonalData() {
//     Navigator.push(context, MaterialPageRoute(
//       builder: (_) => _PersonalDataScreen(name: _name, email: _email),
//     ));
//   }

//   void _navigateToSecurity() {
//     Navigator.push(context, MaterialPageRoute(
//       builder: (_) => _SecurityScreen(
//         bioLoading:   _bioLoading,
//         bioSupported: _bioSupported,
//         bioTypeName:  _bioTypeName,
//         bioEnabled:   _bioEnabled,
//         onToggle:     _toggleBiometric,
//       ),
//     ));
//   }

//   void _snack(String msg, {Color color = AppColors.primary}) {
//     if (!mounted) return;
//     ScaffoldMessenger.of(context).showSnackBar(SnackBar(
//       content: Text(msg), backgroundColor: color,
//       behavior: SnackBarBehavior.floating,
//       shape: RoundedRectangleBorder(
//           borderRadius: BorderRadius.circular(AppRadii.md)),
//     ));
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       backgroundColor: const Color(0xFFEFF6EE),
//       body: SafeArea(
//         child: _loadingUser
//             ? const Center(
//                 child: CircularProgressIndicator(color: AppColors.primary))
//             : SingleChildScrollView(
//                 child: Column(children: [
//                   // Inline header
//                   Padding(
//                     padding: const EdgeInsets.fromLTRB(
//                         AppSpacing.md, AppSpacing.md, AppSpacing.md, 0),
//                     child: Row(children: [
//                       GestureDetector(
//                         onTap: () => Navigator.pop(context),
//                         child: Container(
//                           padding: const EdgeInsets.all(AppSpacing.sm),
//                           decoration: BoxDecoration(
//                             color: AppColors.primarySoft(0.1),
//                             borderRadius: BorderRadius.circular(AppRadii.md),
//                           ),
//                           child: const Icon(Icons.arrow_back_ios_new_rounded,
//                               color: AppColors.primary, size: 18),
//                         ),
//                       ),
//                       const SizedBox(width: AppSpacing.md),
//                       const Text('My Profile', style: AppText.h1),
//                     ]),
//                   ),

//                   const SizedBox(height: AppSpacing.md),

//                   _ProfileHeader(
//                       name: _name, role: 'Admin',
//                       icon: Icons.admin_panel_settings_rounded),

//                   const SizedBox(height: AppSpacing.md),

//                   // Admin: personal data + security + logout (no notifications)
//                   _MenuCard(items: [
//                     _MenuItem(
//                       icon: Icons.person_outline_rounded,
//                       title: 'Personal Data',
//                       subtitle: 'View and manage your information',
//                       onTap: _navigateToPersonalData,
//                     ),
//                     _MenuItem(
//                       icon: Icons.security_rounded,
//                       title: 'Security',
//                       subtitle: 'Biometric & password settings',
//                       onTap: _navigateToSecurity,
//                     ),
//                     _MenuItem(
//                       icon: Icons.logout_rounded,
//                       title: 'Log Out',
//                       subtitle: 'Sign out from your account',
//                       onTap: _showLogoutConfirmation,
//                     ),
//                   ]),

//                   const SizedBox(height: AppSpacing.xl),
//                 ]),
//               ),
//       ),
//     );
//   }
// }

// // ─────────────────────────────────────────────────────────────────────────────
// // Shared sub-screens
// // ─────────────────────────────────────────────────────────────────────────────

// class _PersonalDataScreen extends StatelessWidget {
//   final String name;
//   final String email;
//   const _PersonalDataScreen({required this.name, required this.email});

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       backgroundColor: const Color(0xFFEFF6EE),
//       body: SafeArea(
//         child: SingleChildScrollView(
//           padding: const EdgeInsets.all(AppSpacing.md),
//           child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
//             Row(children: [
//               GestureDetector(
//                 onTap: () => Navigator.pop(context),
//                 child: Container(
//                   padding: const EdgeInsets.all(AppSpacing.sm),
//                   decoration: BoxDecoration(
//                     color: AppColors.primarySoft(0.1),
//                     borderRadius: BorderRadius.circular(AppRadii.md),
//                   ),
//                   child: const Icon(Icons.arrow_back_ios_new_rounded,
//                       color: AppColors.primary, size: 18),
//                 ),
//               ),
//               const SizedBox(width: AppSpacing.md),
//               const Text('Personal Data', style: AppText.h1),
//             ]),
//             const SizedBox(height: AppSpacing.lg),
//             _SectionCard(
//               title: 'Account Information',
//               children: [
//                 _InfoRow(icon: Icons.badge_outlined,
//                     label: 'Display Name',
//                     value: name.isNotEmpty ? name : 'Not set'),
//                 const Divider(height: 1, indent: 40),
//                 _InfoRow(icon: Icons.email_outlined,
//                     label: 'Email Address', value: email),
//               ],
//             ),
//           ]),
//         ),
//       ),
//     );
//   }
// }

// class _SecurityScreen extends StatelessWidget {
//   final bool bioLoading;
//   final bool bioSupported;
//   final String bioTypeName;
//   final bool bioEnabled;
//   final Function(bool) onToggle;

//   const _SecurityScreen({
//     required this.bioLoading,
//     required this.bioSupported,
//     required this.bioTypeName,
//     required this.bioEnabled,
//     required this.onToggle,
//   });

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       backgroundColor: const Color(0xFFEFF6EE),
//       body: SafeArea(
//         child: Padding(
//           padding: const EdgeInsets.all(AppSpacing.md),
//           child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
//             Row(children: [
//               GestureDetector(
//                 onTap: () => Navigator.pop(context),
//                 child: Container(
//                   padding: const EdgeInsets.all(AppSpacing.sm),
//                   decoration: BoxDecoration(
//                     color: AppColors.primarySoft(0.1),
//                     borderRadius: BorderRadius.circular(AppRadii.md),
//                   ),
//                   child: const Icon(Icons.arrow_back_ios_new_rounded,
//                       color: AppColors.primary, size: 18),
//                 ),
//               ),
//               const SizedBox(width: AppSpacing.md),
//               const Text('Security', style: AppText.h1),
//             ]),
//             const SizedBox(height: AppSpacing.lg),
//             _SectionCard(
//               title: 'Biometric Authentication',
//               children: [
//                 Padding(
//                   padding: const EdgeInsets.all(AppSpacing.md),
//                   child: bioLoading
//                       ? const Center(
//                           child: CircularProgressIndicator(
//                               strokeWidth: 2, color: AppColors.primary))
//                       : bioSupported
//                           ? SwitchListTile(
//                               contentPadding: EdgeInsets.zero,
//                               title: Text(bioTypeName,
//                                   style: const TextStyle(
//                                       fontWeight: FontWeight.w600,
//                                       fontSize: 15)),
//                               subtitle: const Text(
//                                   'Use biometrics to sign in quickly'),
//                               value: bioEnabled,
//                               activeColor: AppColors.primary,
//                               onChanged: onToggle,
//                             )
//                           : const Padding(
//                               padding: EdgeInsets.symmetric(vertical: 16),
//                               child: Row(children: [
//                                 Icon(Icons.fingerprint_outlined,
//                                     size: 24, color: Colors.grey),
//                                 SizedBox(width: 16),
//                                 Expanded(
//                                   child: Text(
//                                     'Biometrics not available on this device',
//                                     style: TextStyle(
//                                         fontSize: 14, color: Colors.grey),
//                                   ),
//                                 ),
//                               ]),
//                             ),
//                 ),
//               ],
//             ),
//             const SizedBox(height: AppSpacing.md),
//             _SectionCard(
//               title: 'Password',
//               children: [
//                 ListTile(
//                   leading: Container(
//                     padding: const EdgeInsets.all(AppSpacing.sm),
//                     decoration: BoxDecoration(
//                       color: AppColors.primarySoft(0.1),
//                       borderRadius: BorderRadius.circular(AppRadii.md),
//                     ),
//                     child: const Icon(Icons.lock_reset_outlined,
//                         color: AppColors.primary, size: 22),
//                   ),
//                   title: const Text('Change Password',
//                       style: TextStyle(
//                           fontSize: 15, fontWeight: FontWeight.w600)),
//                   subtitle: const Text('Update your password',
//                       style: TextStyle(fontSize: 12, color: Colors.grey)),
//                   trailing: const Icon(Icons.chevron_right_rounded,
//                       color: Colors.grey),
//                   onTap: () => Navigator.push(context,
//                       MaterialPageRoute(
//                           builder: (_) => const ResetInAppScreen())),
//                 ),
//               ],
//             ),
//           ]),
//         ),
//       ),
//     );
//   }
// }

// // ─────────────────────────────────────────────────────────────────────────────
// // Shared widgets (same pattern as parent_profile_screen.dart)
// // ─────────────────────────────────────────────────────────────────────────────

// class _ProfileHeader extends StatelessWidget {
//   final String name;
//   final String role;
//   final IconData icon;
//   const _ProfileHeader(
//       {required this.name, required this.role, required this.icon});

//   @override
//   Widget build(BuildContext context) => Container(
//         width: double.infinity,
//         margin: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
//         padding: const EdgeInsets.symmetric(
//             vertical: AppSpacing.xl, horizontal: AppSpacing.lg),
//         decoration: BoxDecoration(
//           gradient: AppDecorations.primaryGradient,
//           borderRadius: BorderRadius.circular(AppRadii.lg),
//           boxShadow: [
//             BoxShadow(
//               color: AppColors.primary.withOpacity(0.25),
//               offset: const Offset(0, 6),
//               blurRadius: 16,
//             ),
//           ],
//         ),
//         child: Column(children: [
//           Container(
//             decoration: BoxDecoration(
//               shape: BoxShape.circle,
//               border: Border.all(color: Colors.white, width: 3),
//             ),
//             child: CircleAvatar(
//               radius: 44,
//               backgroundColor: Colors.white.withOpacity(0.25),
//               child: Icon(icon, color: Colors.white, size: 40),
//             ),
//           ),
//           const SizedBox(height: AppSpacing.md),
//           Text(name.isNotEmpty ? name : role,
//               style: const TextStyle(
//                   color: Colors.white,
//                   fontSize: 22,
//                   fontWeight: FontWeight.bold)),
//           const SizedBox(height: AppSpacing.sm),
//           Container(
//             padding: const EdgeInsets.symmetric(
//                 horizontal: AppSpacing.md, vertical: AppSpacing.xs + 2),
//             decoration: BoxDecoration(
//               color: Colors.white.withOpacity(0.2),
//               borderRadius: BorderRadius.circular(AppRadii.pill),
//             ),
//             child: Text(role,
//                 style: const TextStyle(
//                     color: Colors.white,
//                     fontSize: 12,
//                     fontWeight: FontWeight.w600)),
//           ),
//         ]),
//       );
// }

// class _MenuCard extends StatelessWidget {
//   final List<_MenuItem> items;
//   const _MenuCard({required this.items});

//   @override
//   Widget build(BuildContext context) => Container(
//         margin: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
//         decoration: BoxDecoration(
//           color: Colors.white,
//           borderRadius: BorderRadius.circular(AppRadii.lg),
//           boxShadow: [
//             BoxShadow(
//               color: Colors.black.withOpacity(0.05),
//               blurRadius: 10, offset: const Offset(0, 3),
//             ),
//           ],
//         ),
//         child: Column(
//           children: List.generate(items.length, (i) {
//             final isLast = i == items.length - 1;
//             return Column(children: [
//               _MenuTile(item: items[i]),
//               if (!isLast)
//                 const Divider(height: 1, indent: 56, endIndent: 16),
//             ]);
//           }),
//         ),
//       );
// }

// class _MenuItem {
//   final IconData icon;
//   final String title;
//   final String subtitle;
//   final VoidCallback onTap;
//   final bool isDestructive;
//   final Widget? trailing;

//   const _MenuItem({
//     required this.icon,
//     required this.title,
//     required this.subtitle,
//     required this.onTap,
//     this.isDestructive = false,
//     this.trailing,
//   });
// }

// class _MenuTile extends StatelessWidget {
//   final _MenuItem item;
//   const _MenuTile({required this.item});

//   @override
//   Widget build(BuildContext context) => ListTile(
//         leading: Container(
//           padding: const EdgeInsets.all(AppSpacing.sm),
//           decoration: BoxDecoration(
//             color: item.isDestructive
//                 ? Colors.red.shade50
//                 : AppColors.primarySoft(0.1),
//             borderRadius: BorderRadius.circular(AppRadii.md),
//           ),
//           child: Icon(item.icon,
//               color: item.isDestructive ? Colors.red : AppColors.primary,
//               size: 22),
//         ),
//         title: Text(item.title,
//             style: TextStyle(
//                 fontSize: 15,
//                 fontWeight: FontWeight.w600,
//                 color: item.isDestructive ? Colors.red : Colors.black87)),
//         subtitle: Text(item.subtitle,
//             style: const TextStyle(fontSize: 12, color: Colors.grey)),
//         trailing: item.trailing ??
//             const Icon(Icons.chevron_right_rounded, color: Colors.grey),
//         onTap: item.onTap,
//       );
// }

// class _SectionCard extends StatelessWidget {
//   final String title;
//   final Color titleColor;
//   final List<Widget> children;

//   const _SectionCard({
//     required this.title,
//     this.titleColor = AppColors.primary,
//     required this.children,
//   });

//   @override
//   Widget build(BuildContext context) => Container(
//         width: double.infinity,
//         decoration: BoxDecoration(
//           color: Colors.white,
//           borderRadius: BorderRadius.circular(AppRadii.lg),
//           boxShadow: [
//             BoxShadow(
//               color: Colors.black.withOpacity(0.05),
//               blurRadius: 10, offset: const Offset(0, 3),
//             ),
//           ],
//         ),
//         child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
//           Padding(
//             padding: const EdgeInsets.fromLTRB(
//                 AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.sm),
//             child: Text(title,
//                 style: TextStyle(
//                     fontSize: 14,
//                     fontWeight: FontWeight.bold,
//                     color: titleColor)),
//           ),
//           const Divider(height: 1, indent: 16, endIndent: 16),
//           ...children,
//         ]),
//       );
// }

// class _InfoRow extends StatelessWidget {
//   final IconData icon;
//   final String label;
//   final String value;
//   const _InfoRow(
//       {required this.icon, required this.label, required this.value});

//   @override
//   Widget build(BuildContext context) => Padding(
//         padding: const EdgeInsets.symmetric(
//             horizontal: AppSpacing.md, vertical: AppSpacing.md - 2),
//         child: Row(children: [
//           Icon(icon, size: 20, color: AppColors.primarySoft(0.7)),
//           const SizedBox(width: AppSpacing.md),
//           Expanded(
//             child: Column(
//                 crossAxisAlignment: CrossAxisAlignment.start,
//                 children: [
//               Text(label,
//                   style: const TextStyle(
//                       fontSize: 11,
//                       color: Colors.grey,
//                       fontWeight: FontWeight.w500)),
//               const SizedBox(height: 2),
//               Text(value,
//                   style: const TextStyle(
//                       fontSize: 15,
//                       fontWeight: FontWeight.w600,
//                       color: Colors.black87)),
//             ]),
//           ),
//         ]),
//       );
// }