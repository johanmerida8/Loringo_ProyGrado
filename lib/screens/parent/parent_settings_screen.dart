// import 'package:firebase_auth/firebase_auth.dart';
// import 'package:flutter/material.dart';
// import 'package:local_auth/local_auth.dart';
// import 'package:loringo_app/services/auth/biometric_service.dart';

// class ParentSettingsScreen extends StatefulWidget {
//   const ParentSettingsScreen({super.key});

//   @override
//   State<ParentSettingsScreen> createState() => _ParentSettingsScreenState();
// }

// class _ParentSettingsScreenState extends State<ParentSettingsScreen> {
//   bool isBiometricSupported = false;
//   bool isBiometricEnabled = false;
//   bool isLoading = true;
//   List<BiometricType> availableBiometrics = [];
//   String biometricTypeName = 'Biometrics';

//   @override
//   void initState() {
//     super.initState();
//     _initBiometrics();
//   }

//   Future<void> _initBiometrics() async {
//     final userId = FirebaseAuth.instance.currentUser?.uid;
//     if (userId == null) return;

//     try {
//       final isSupported = await BiometricService.isDeviceSupported();
//       final canCheck = await BiometricService.canCheckBiometrics();
//       final available = await BiometricService.getAvailableBiometrics();
//       final isEnabled = await BiometricService.isBiometricEnabled(userId);

//       setState(() {
//         isBiometricSupported = isSupported && canCheck;
//         availableBiometrics = available;
//         biometricTypeName = BiometricService.getBiometricTypeName(available);
//         isBiometricEnabled = isEnabled;
//         isLoading = false;
//       });
//     } catch (e) {
//       print('Error initializing biometrics: $e');
//       setState(() => isLoading = false);
//     }
//   }

//   Future<void> _toggleBiometric(bool value) async {
//     final userId = FirebaseAuth.instance.currentUser?.uid;
//     if (userId == null) return;

//     if (value) {
//       // Verify biometric before enabling
//       final authenticated = await BiometricService.authenticate(
//         reason: 'Verify your identity to enable biometric login',
//       );

//       if (authenticated) {
//         await BiometricService.setBiometricEnabled(
//           userId: userId,
//           enabled: true,
//         );
//         setState(() => isBiometricEnabled = true);
        
//         if (mounted) {
//           ScaffoldMessenger.of(context).showSnackBar(
//             SnackBar(
//               content: Text('✅ $biometricTypeName login enabled'),
//               backgroundColor: Colors.green,
//             ),
//           );
//         }
//       } else {
//         if (mounted) {
//           ScaffoldMessenger.of(context).showSnackBar(
//             const SnackBar(
//               content: Text('❌ Authentication failed'),
//               backgroundColor: Colors.red,
//             ),
//           );
//         }
//       }
//     } else {
//       await BiometricService.setBiometricEnabled(
//         userId: userId,
//         enabled: false,
//       );
//       setState(() => isBiometricEnabled = false);
      
//       if (mounted) {
//         ScaffoldMessenger.of(context).showSnackBar(
//           SnackBar(
//             content: Text('$biometricTypeName login disabled'),
//             backgroundColor: Colors.grey,
//           ),
//         );
//       }
//     }
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       backgroundColor: const Color(0xFFFAEDCA),
//       appBar: AppBar(
//         backgroundColor: const Color(0xFFFFCFB3),
//         elevation: 0,
//         title: const Text(
//           'Settings',
//           style: TextStyle(
//             color: Colors.white,
//             fontWeight: FontWeight.bold,
//             fontSize: 24,
//           ),
//         ),
//         leading: IconButton(
//           icon: const Icon(Icons.arrow_back, color: Colors.white),
//           onPressed: () => Navigator.pop(context),
//         ),
//       ),
//       body: isLoading
//           ? const Center(child: CircularProgressIndicator())
//           : SingleChildScrollView(
//               child: Padding(
//                 padding: const EdgeInsets.all(20.0),
//                 child: Column(
//                   crossAxisAlignment: CrossAxisAlignment.start,
//                   children: [
//                     // Security Section
//                     Container(
//                       width: double.infinity,
//                       padding: const EdgeInsets.all(20),
//                       decoration: BoxDecoration(
//                         color: Colors.white,
//                         borderRadius: BorderRadius.circular(16),
//                         boxShadow: [
//                           BoxShadow(
//                             color: Colors.black.withOpacity(0.05),
//                             blurRadius: 10,
//                             offset: const Offset(0, 5),
//                           ),
//                         ],
//                       ),
//                       child: Column(
//                         crossAxisAlignment: CrossAxisAlignment.start,
//                         children: [
//                           Row(
//                             children: [
//                               Container(
//                                 padding: const EdgeInsets.all(10),
//                                 decoration: BoxDecoration(
//                                   color: const Color(0xFFFFCFB3).withOpacity(0.2),
//                                   borderRadius: BorderRadius.circular(10),
//                                 ),
//                                 child: const Icon(
//                                   Icons.security_rounded,
//                                   color: Color(0xFFFFCFB3),
//                                   size: 28,
//                                 ),
//                               ),
//                               const SizedBox(width: 12),
//                               const Text(
//                                 'Security',
//                                 style: TextStyle(
//                                   fontSize: 20,
//                                   fontWeight: FontWeight.bold,
//                                   color: Color(0xFFFE5D26),
//                                 ),
//                               ),
//                             ],
//                           ),
//                           const SizedBox(height: 20),
                          
//                           // Biometric Authentication Toggle
//                           if (isBiometricSupported)
//                             Container(
//                               padding: const EdgeInsets.all(16),
//                               decoration: BoxDecoration(
//                                 color: const Color(0xFFFAEDCA).withOpacity(0.3),
//                                 borderRadius: BorderRadius.circular(12),
//                               ),
//                               child: Row(
//                                 children: [
//                                   Icon(
//                                     availableBiometrics.contains(BiometricType.face)
//                                         ? Icons.face_rounded
//                                         : Icons.fingerprint_rounded,
//                                     size: 32,
//                                     color: const Color(0xFFFE5D26),
//                                   ),
//                                   const SizedBox(width: 16),
//                                   Expanded(
//                                     child: Column(
//                                       crossAxisAlignment: CrossAxisAlignment.start,
//                                       children: [
//                                         Text(
//                                           '$biometricTypeName Login',
//                                           style: const TextStyle(
//                                             fontSize: 16,
//                                             fontWeight: FontWeight.bold,
//                                           ),
//                                         ),
//                                         const SizedBox(height: 4),
//                                         Text(
//                                           'Quick and secure login',
//                                           style: TextStyle(
//                                             fontSize: 13,
//                                             color: Colors.grey[600],
//                                           ),
//                                         ),
//                                       ],
//                                     ),
//                                   ),
//                                   Switch(
//                                     value: isBiometricEnabled,
//                                     onChanged: _toggleBiometric,
//                                     activeColor: const Color(0xFFA2CA71),
//                                   ),
//                                 ],
//                               ),
//                             )
//                           else
//                             Container(
//                               padding: const EdgeInsets.all(16),
//                               decoration: BoxDecoration(
//                                 color: Colors.grey[200],
//                                 borderRadius: BorderRadius.circular(12),
//                               ),
//                               child: Row(
//                                 children: [
//                                   Icon(
//                                     Icons.fingerprint_rounded,
//                                     size: 32,
//                                     color: Colors.grey[400],
//                                   ),
//                                   const SizedBox(width: 16),
//                                   Expanded(
//                                     child: Column(
//                                       crossAxisAlignment: CrossAxisAlignment.start,
//                                       children: [
//                                         Text(
//                                           'Biometric Login',
//                                           style: TextStyle(
//                                             fontSize: 16,
//                                             fontWeight: FontWeight.bold,
//                                             color: Colors.grey[600],
//                                           ),
//                                         ),
//                                         const SizedBox(height: 4),
//                                         Text(
//                                           'Not available on this device',
//                                           style: TextStyle(
//                                             fontSize: 13,
//                                             color: Colors.grey[500],
//                                           ),
//                                         ),
//                                       ],
//                                     ),
//                                   ),
//                                 ],
//                               ),
//                             ),
//                         ],
//                       ),
//                     ),

//                     const SizedBox(height: 20),

//                     // Account Info Section
//                     Container(
//                       width: double.infinity,
//                       padding: const EdgeInsets.all(20),
//                       decoration: BoxDecoration(
//                         color: Colors.white,
//                         borderRadius: BorderRadius.circular(16),
//                         boxShadow: [
//                           BoxShadow(
//                             color: Colors.black.withOpacity(0.05),
//                             blurRadius: 10,
//                             offset: const Offset(0, 5),
//                           ),
//                         ],
//                       ),
//                       child: Column(
//                         crossAxisAlignment: CrossAxisAlignment.start,
//                         children: [
//                           Row(
//                             children: [
//                               Container(
//                                 padding: const EdgeInsets.all(10),
//                                 decoration: BoxDecoration(
//                                   color: const Color(0xFFB7E0FF).withOpacity(0.2),
//                                   borderRadius: BorderRadius.circular(10),
//                                 ),
//                                 child: const Icon(
//                                   Icons.person_rounded,
//                                   color: Color(0xFFB7E0FF),
//                                   size: 28,
//                                 ),
//                               ),
//                               const SizedBox(width: 12),
//                               const Text(
//                                 'Account',
//                                 style: TextStyle(
//                                   fontSize: 20,
//                                   fontWeight: FontWeight.bold,
//                                   color: Color(0xFFFE5D26),
//                                 ),
//                               ),
//                             ],
//                           ),
//                           const SizedBox(height: 20),
                          
//                           // Email Display
//                           ListTile(
//                             leading: const Icon(Icons.email_rounded, color: Color(0xFFB7E0FF)),
//                             title: const Text('Email'),
//                             subtitle: Text(
//                               FirebaseAuth.instance.currentUser?.email ?? 'Not available',
//                               style: const TextStyle(fontWeight: FontWeight.w600),
//                             ),
//                           ),
//                         ],
//                       ),
//                     ),
//                   ],
//                 ),
//               ),
//             ),
//     );
//   }
// }
