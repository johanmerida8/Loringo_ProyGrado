import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// Parent Join Group Screen
/// Parent enters group code to join their child to the group
class ParentJoinGroupScreen extends StatefulWidget {
  final Map<String, dynamic> child;

  const ParentJoinGroupScreen({super.key, required this.child});

  @override
  State<ParentJoinGroupScreen> createState() => _ParentJoinGroupScreenState();
}

class _ParentJoinGroupScreenState extends State<ParentJoinGroupScreen> {
  final groupCodeController = TextEditingController();
  bool isLoading = false;

  @override
  void dispose() {
    groupCodeController.dispose();
    super.dispose();
  }

  /// Join child to group using group code
  void _joinGroup() async {
    if (groupCodeController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter the group code')),
      );
      return;
    }

    setState(() => isLoading = true);

    try {
      // Find group by code
      final groupSnapshot = await FirebaseFirestore.instance
          .collection('teacherGroups')
          .where(
            'groupCode',
            isEqualTo: groupCodeController.text.trim().toUpperCase(),
          )
          .get();

      if (groupSnapshot.docs.isEmpty) {
        throw Exception('Invalid group code');
      }

      final groupDoc = groupSnapshot.docs.first;
      final groupId = groupDoc.id;
      final groupName = groupDoc.data()['name'] as String;
      final studentId = widget.child['id'];

      // Update student with groupId
      await FirebaseFirestore.instance
          .collection('students')
          .doc(studentId)
          .update({
            'groupId': groupId,
            'lastUpdate': FieldValue.serverTimestamp(),
          });

      // Create subcollection entry in the group using student UID
      await FirebaseFirestore.instance
          .collection('teacherGroups')
          .doc(groupId)
          .collection('students')
          .doc(studentId)
          .set({
            'studentId': studentId,
            'joinedAt': FieldValue.serverTimestamp(),
          });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✅ ${widget.child['names']} joined the group: $groupName',
            ),
            backgroundColor: const Color(0xFFA2CA71),
          ),
        );
        Navigator.pop(context, true); // Return true to indicate success
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAEDCA),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFFCFB3),
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back, color: Colors.white),
        ),
        title: const Text(
          'Join Group',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 20),

                // Info Card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFFB7E0FF).withOpacity(0.3),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: const Color(0xFFB7E0FF),
                      width: 2,
                    ),
                  ),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.school_rounded,
                        size: 60,
                        color: Color(0xFF4A90E2),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        widget.child['names'] ?? 'Your child',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFFE5D26),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'will join the group',
                        style: TextStyle(fontSize: 16, color: Colors.black87),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 40),

                const Text(
                  'Group Code',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFFE5D26),
                  ),
                ),

                const SizedBox(height: 8),

                Text(
                  'Enter the 6-character code shared by the teacher',
                  style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                ),

                const SizedBox(height: 20),

                // Group code textfield
                TextField(
                  controller: groupCodeController,
                  textCapitalization: TextCapitalization.characters,
                  maxLength: 6,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 4,
                  ),
                  decoration: InputDecoration(
                    hintText: 'ABC123',
                    hintStyle: TextStyle(
                      color: Colors.grey[400],
                      letterSpacing: 4,
                    ),
                    prefixIcon: const Icon(
                      Icons.vpn_key_rounded,
                      color: Color(0xFFFFCFB3),
                      size: 28,
                    ),
                    filled: true,
                    fillColor: Colors.white,
                    counterText: '',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(
                        color: Colors.grey.shade300,
                        width: 2,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(
                        color: Color(0xFFFFCFB3),
                        width: 2,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 40),

                // Join button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: isLoading ? null : _joinGroup,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFCFB3),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey[300],
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 4,
                    ),
                    child: isLoading
                        ? const SizedBox(
                            height: 24,
                            width: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'Join Group',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),

                const SizedBox(height: 20),

                // Info message
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFA2CA71).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.info_outline_rounded,
                        color: Color(0xFFA2CA71),
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'The code is provided by the teacher of the group you want to join',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[800],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
