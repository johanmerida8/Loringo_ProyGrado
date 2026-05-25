import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:loringo_app/components/app_drawer.dart';
import 'package:loringo_app/screens/teacher/group_activities_screen.dart';
import 'package:loringo_app/screens/teacher/student_progress_dashboard.dart';
import 'package:loringo_app/screens/teacher/teacher_level_screen.dart';
import 'package:loringo_app/services/auth/auth_gate.dart';
import 'package:loringo_app/theme/app_theme.dart';

class TeacherGroupDetailsScreen extends StatefulWidget {
  final String groupId;
  final String groupName;
  final String groupCode;
  final Color groupColor;

  const TeacherGroupDetailsScreen({
    super.key,
    required this.groupId,
    required this.groupName,
    required this.groupCode,
    required this.groupColor,
  });

  @override
  State<TeacherGroupDetailsScreen> createState() =>
      _TeacherGroupDetailsScreenState();
}

class _TeacherGroupDetailsScreenState
    extends State<TeacherGroupDetailsScreen> {
  int _currentIndex = 0;
  List<Map<String, dynamic>> _students = [];
  Map<String, dynamic>? _teacherData;
  bool isLoadingMembers = false;
  late String _groupName;
  String _userName = '';

  // Settings form state
  final _settingsNameController = TextEditingController();
  int _settingsYear = DateTime.now().year;
  int _settingsPeriod = 1;
  Color _settingsColor = AppColors.primary;
  bool _savingSettings = false;

  // Original values — used to detect changes
  String _originalName = '';
  int _originalYear = DateTime.now().year;
  int _originalPeriod = 1;
  Color _originalColor = AppColors.primary;

  // Cached activity map data — loaded once, reused for full screen
  List<Map<String, dynamic>>? _contentItems;

  static const List<Color> _availableColors = [
    AppColors.primary,
    Color(0xFF2196F3),
    Color(0xFFFF9800),
    Color(0xFFE91E63),
    Color(0xFF9C27B0),
    Color(0xFFFFEB3B),
    Color(0xFF00BCD4),
    Color(0xFFFF5722),
  ];

  List<int> get _years {
    final current = DateTime.now().year;
    return List.generate(5, (i) => current + i);
  }

  @override
  void initState() {
    super.initState();
    _groupName = widget.groupName;
    _loadGroupMembers();
    _loadUserName();
    _loadGroupSettings();
  }

  @override
  void dispose() {
    _settingsNameController.dispose();
    super.dispose();
  }

  Future<void> _loadGroupSettings() async {
    final doc = await FirebaseFirestore.instance
        .collection('teacherGroups')
        .doc(widget.groupId)
        .get();
    if (!mounted) return;
    final data = doc.data();
    if (data == null) return;
    final colorHex = (data['color'] as String? ?? '').replaceAll('#', '');
    Color parsed = AppColors.primary;
    try {
      parsed = Color(int.parse('FF$colorHex', radix: 16));
    } catch (_) {}
    final name = data['name'] as String? ?? '';
    final year = (data['academicYear'] as int?) ?? DateTime.now().year;
    final period = (data['period'] as int?) ?? 1;
    setState(() {
      _settingsNameController.text = name;
      _settingsYear = year;
      _settingsPeriod = period;
      _settingsColor = parsed;
      // Store originals
      _originalName = name;
      _originalYear = year;
      _originalPeriod = period;
      _originalColor = parsed;
    });
  }

  bool get _settingsHaveChanged =>
      _settingsNameController.text.trim() != _originalName ||
      _settingsYear != _originalYear ||
      _settingsPeriod != _originalPeriod ||
      _settingsColor.value != _originalColor.value;

  Future<void> _saveGroupSettings() async {
    final name = _settingsNameController.text.trim();
    if (name.isEmpty) return;

    if (!_settingsHaveChanged) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No changes made'),
          backgroundColor: Colors.grey,
        ),
      );
      return;
    }

    setState(() => _savingSettings = true);
    final colorHex =
        '#${_settingsColor.value.toRadixString(16).substring(2).toUpperCase()}';
    try {
      await FirebaseFirestore.instance
          .collection('teacherGroups')
          .doc(widget.groupId)
          .update({
        'name': name,
        'academicYear': _settingsYear,
        'period': _settingsPeriod,
        'color': colorHex,
      });
      if (mounted) {
        setState(() {
          _groupName = name;
          // Update originals so a second save also detects no change
          _originalName = name;
          _originalYear = _settingsYear;
          _originalPeriod = _settingsPeriod;
          _originalColor = _settingsColor;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Changes saved'),
            backgroundColor: AppColors.primary,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _savingSettings = false);
    }
  }

  Future<void> _deleteGroup() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Group'),
        content: Text(
            'Are you sure you want to delete "$_groupName"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      await FirebaseFirestore.instance
          .collection('teacherGroups')
          .doc(widget.groupId)
          .delete();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _loadUserName() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();
    final name = (doc.data()?['name'] as String?) ?? '';
    if (mounted && name.isNotEmpty) setState(() => _userName = name);
  }

  // -- Data loading ---------------------------------------------------------

  Future<void> _loadGroupMembers() async {
    setState(() => isLoadingMembers = true);
    try {
      final groupDoc = await FirebaseFirestore.instance
          .collection('teacherGroups')
          .doc(widget.groupId)
          .get();

      if (groupDoc.exists) {
        final teacherId = groupDoc.data()!['teacherId'];
        final teacherDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(teacherId)
            .get();
        if (teacherDoc.exists) _teacherData = teacherDoc.data();
      }

      final studentsSnapshot = await FirebaseFirestore.instance
          .collection('students')
          .where('groupId', isEqualTo: widget.groupId)
          .get();

      final studentsList = <Map<String, dynamic>>[];
      for (var doc in studentsSnapshot.docs) {
        final data = doc.data();
        final parentId = data['parentId'];
        String parentEmail = '';
        if (parentId != null) {
          final parentDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(parentId)
              .get();
          if (parentDoc.exists) parentEmail = parentDoc.data()?['email'] ?? '';
        }
        studentsList.add({
          'id': doc.id,
          'name': data['names'] ?? 'No name',
          'avatar': data['avatar'] ?? '',
          'accessCode': data['accessCode'] ?? '',
          'parentId': parentId ?? '',
          'parentEmail': parentEmail,
          'joinedAt': data['createdAt'],
        });
      }
      studentsList.sort((a, b) =>
          (a['name'] as String).compareTo(b['name']));

      setState(() {
        _students = studentsList;
        isLoadingMembers = false;
      });
    } catch (e) {
      print('Error loading group members: $e');
      setState(() {
        _students = [];
        isLoadingMembers = false;
      });
    }
  }

  // -- Helpers --------------------------------------------------------------

  void _copyCodeToClipboard() {
    Clipboard.setData(ClipboardData(text: widget.groupCode));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('? Code copied to clipboard'),
        backgroundColor: Color(0xFF4CAF50),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _removeStudent(String studentId, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Student'),
        content: Text('Are you sure you want to remove $name from the group?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await FirebaseFirestore.instance
            .collection('students')
            .doc(studentId)
            .update({
          'groupId': FieldValue.delete(),
          'lastUpdate': FieldValue.serverTimestamp(),
        });
        await FirebaseFirestore.instance
            .collection('teacherGroups')
            .doc(widget.groupId)
            .collection('students')
            .doc(studentId)
            .delete();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Student removed from group'),
              backgroundColor: Colors.orange,
            ),
          );
          _loadGroupMembers();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  void _showInviteStudentModal() {
    final emailController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (modalCtx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
        ),
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
          left: 24,
          right: 24,
          top: 24,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.person_add,
                          color: Color(0xFF4CAF50), size: 28),
                      const SizedBox(width: 12),
                      const Text(
                        'Invite Student',
                        style: TextStyle(
                            fontSize: 24, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  IconButton(
                    onPressed: () {
                      emailController.dispose();
                      Navigator.pop(context);
                    },
                    icon: const Icon(Icons.close),
                    color: Colors.grey[600],
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // Group code card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      widget.groupColor,
                      widget.groupColor.withOpacity(0.8)
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    const Text('Group Code',
                        style: TextStyle(
                            fontSize: 14, color: Colors.white70)),
                    const SizedBox(height: 8),
                    Text(
                      widget.groupCode,
                      style: const TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 4),
                    ),
                    const SizedBox(height: 4),
                    Text(widget.groupName,
                        style:
                            const TextStyle(fontSize: 14, color: Colors.white70),
                        textAlign: TextAlign.center),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _copyCodeToClipboard,
                  icon: const Icon(Icons.copy_rounded),
                  label: const Text('Copy Code',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: widget.groupColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(child: Divider(color: Colors.grey[300])),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text('OR',
                        style: TextStyle(
                            color: Colors.grey[600],
                            fontWeight: FontWeight.bold)),
                  ),
                  Expanded(child: Divider(color: Colors.grey[300])),
                ],
              ),
              const SizedBox(height: 24),
              Text('Send Direct Invitation',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[800])),
              const SizedBox(height: 8),
              Text("Enter parent's email to send a group invitation",
                  style: TextStyle(fontSize: 13, color: Colors.grey[600])),
              const SizedBox(height: 16),
              TextField(
                controller: emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: 'Parent Email',
                  hintText: 'example@email.com',
                  prefixIcon: const Icon(Icons.email_outlined),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey[300]!)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          const BorderSide(color: Color(0xFF4CAF50), width: 2)),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    final email = emailController.text.trim();
                    if (email.isEmpty ||
                        !RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$')
                            .hasMatch(email)) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Please enter a valid email'),
                            backgroundColor: Colors.orange),
                      );
                      return;
                    }
                    try {
                      final userSnapshot = await FirebaseFirestore.instance
                          .collection('users')
                          .where('email', isEqualTo: email)
                          .where('role', isEqualTo: 'parent')
                          .limit(1)
                          .get();

                      if (userSnapshot.docs.isEmpty) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content:
                                    Text('No parent found with that email'),
                                backgroundColor: Colors.orange),
                          );
                        }
                        return;
                      }

                      final parentId = userSnapshot.docs.first.id;
                      await FirebaseFirestore.instance
                          .collection('notifications')
                          .add({
                        'userId': parentId,
                        'type': 'group_invitation',
                        'title': 'Group Invitation',
                        'message':
                            'You have been invited to the group ${widget.groupName}',
                        'data': {
                          'groupId': widget.groupId,
                          'groupName': widget.groupName,
                          'groupCode': widget.groupCode,
                        },
                        'isRead': false,
                        'createdAt': FieldValue.serverTimestamp(),
                      });

                      emailController.dispose();
                      if (mounted) Navigator.pop(context);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content: Text('? Invitation sent to $email'),
                              backgroundColor: const Color(0xFF4CAF50)),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content: Text('? Error: $e'),
                              backgroundColor: Colors.red),
                        );
                      }
                    }
                  },
                  icon: const Icon(Icons.send_rounded),
                  label: const Text('Send Invitation',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[600],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  // -- Tab builders ----------------------------------------------------------

  Widget _buildContentTab() {
    return Column(
      children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Row(
            children: [
              Text(
                'Content Map',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[800],
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    fullscreenDialog: true,
                    builder: (_) => GroupActivitiesScreen(
                      groupId: widget.groupId,
                      groupName: widget.groupName,
                      groupColor: widget.groupColor,
                      preloadedItems: _contentItems,
                    ),
                  ),
                ),
                icon: const Icon(Icons.fullscreen_rounded, size: 20),
                label: const Text('Full Screen'),
                style: TextButton.styleFrom(
                    foregroundColor: AppColors.primary),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            child: TeacherLevelScreen(
              groupId: widget.groupId,
              groupName: widget.groupName,
              embedded: true,
              onLoaded: (items) => _contentItems = items,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMembersTab() {
    if (isLoadingMembers) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Teacher',
              style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF4CAF50))),
          const SizedBox(height: 12),
          Card(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            elevation: 2,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: const LinearGradient(
                  colors: [
                    Color(0xFFE8F5E9),
                    Color(0xFFF1F8E9),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.all(16),
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFF4CAF50),
                  radius: 28,
                  child: Icon(Icons.school,
                      color: Colors.white, size: 28),
                ),
                title: Text(_teacherData?['name'] ?? 'Teacher',
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.bold)),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_teacherData?['email'] ?? '',
                        style: const TextStyle(
                            fontSize: 14, color: Colors.black54)),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF4CAF50).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text('Group Owner',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87)),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Students (${_students.length})',
                  style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF4CAF50))),
              IconButton(
                onPressed: _showInviteStudentModal,
                icon: const Icon(Icons.person_add_rounded),
                color: const Color(0xFF4CAF50),
                iconSize: 28,
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_students.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(40),
                child: Column(
                  children: [
                    Icon(Icons.people_outline_rounded,
                        size: 80, color: Colors.grey[400]),
                    const SizedBox(height: 16),
                    Text('No students yet',
                        style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w500)),
                    const SizedBox(height: 8),
                    Text('Tap + to invite students',
                        style: TextStyle(
                            fontSize: 14, color: Colors.grey[500])),
                  ],
                ),
              ),
            )
          else
            ...List.generate(_students.length, (i) {
              final s = _students[i];
              final name = s['name'] as String;
              final parentEmail = s['parentEmail'] as String;
              final avatar = s['avatar'] as String;
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                elevation: 2,
                child: ListTile(
                  contentPadding: const EdgeInsets.all(16),
                  leading: CircleAvatar(
                    backgroundColor:
                        const Color(0xFF4CAF50).withOpacity(0.2),
                    radius: 28,
                    backgroundImage:
                        avatar.isNotEmpty ? AssetImage(avatar) : null,
                    child: avatar.isEmpty
                        ? Text(
                            name.isNotEmpty ? name[0].toUpperCase() : 'E',
                            style: const TextStyle(
                                color: Color(0xFF4CAF50),
                                fontWeight: FontWeight.bold,
                                fontSize: 20))
                        : null,
                  ),
                  title: Text(name,
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.bold)),
                  subtitle: Text(
                    parentEmail.isNotEmpty
                        ? 'Parent: $parentEmail'
                        : 'No parent email',
                    style: const TextStyle(
                        fontSize: 14, color: Colors.black54),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.remove_circle_outline,
                        color: Colors.red),
                    onPressed: () =>
                        _removeStudent(s['id'], name),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildStatisticsTab() {
    if (isLoadingMembers) {
      return const Center(child: CircularProgressIndicator());
    }
    return StudentProgressDashboard(
      groupId: widget.groupId,
      groupName: widget.groupName,
      students: _students,
      showAppBar: false,
    );
  }

  Widget _buildSettingsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Group Settings',
            style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AppColors.primary),
          ),
          const SizedBox(height: 20),

          // ── Group name ──────────────────────────────────────────────────
          _settingsLabel('Group Name', Icons.group_outlined),
          const SizedBox(height: 8),
          TextFormField(
            controller: _settingsNameController,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              hintText: 'Enter group name',
              filled: true,
              fillColor: Colors.white,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey[300]!)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey[300]!)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      const BorderSide(color: AppColors.primary, width: 2)),
            ),
          ),
          const SizedBox(height: 24),

          // ── Academic year ───────────────────────────────────────────────
          _settingsLabel('Academic Year', Icons.calendar_today_outlined),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _years.map((year) {
                final selected = year == _settingsYear;
                return GestureDetector(
                  onTap: () => setState(() => _settingsYear = year),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: const EdgeInsets.only(right: 10),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    decoration: BoxDecoration(
                      color: selected ? AppColors.primary : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: selected
                            ? AppColors.primary
                            : Colors.grey[300]!,
                        width: selected ? 2 : 1,
                      ),
                    ),
                    child: Text(
                      '$year',
                      style: TextStyle(
                        color: selected ? Colors.white : Colors.grey[700],
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 24),

          // ── Period ──────────────────────────────────────────────────────
          _settingsLabel('Period', Icons.timeline_outlined),
          const SizedBox(height: 10),
          Row(
            children: [
              _PeriodOption(
                period: 1,
                label: 'Period 1',
                subtitle: 'Jan – Jun',
                isSelected: _settingsPeriod == 1,
                onTap: () => setState(() => _settingsPeriod = 1),
              ),
              const SizedBox(width: 12),
              _PeriodOption(
                period: 2,
                label: 'Period 2',
                subtitle: 'Jul – Dec',
                isSelected: _settingsPeriod == 2,
                onTap: () => setState(() => _settingsPeriod = 2),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // ── Color ───────────────────────────────────────────────────────
          _settingsLabel('Group Color', Icons.palette_outlined),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: _availableColors.map((color) {
              final selected = color.value == _settingsColor.value;
              return GestureDetector(
                onTap: () => setState(() => _settingsColor = color),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected ? Colors.black54 : Colors.transparent,
                      width: 3,
                    ),
                    boxShadow: selected
                        ? [
                            BoxShadow(
                              color: color.withOpacity(0.5),
                              blurRadius: 8,
                              spreadRadius: 1,
                            )
                          ]
                        : [],
                  ),
                  child: selected
                      ? const Icon(Icons.check,
                          color: Colors.white, size: 22)
                      : null,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 32),

          // ── Save button ─────────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _savingSettings ? null : _saveGroupSettings,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              child: _savingSettings
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Save Changes',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 16),

          // ── Danger zone ─────────────────────────────────────────────────
          const Divider(),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: OutlinedButton.icon(
              onPressed: _deleteGroup,
              icon: const Icon(Icons.delete_rounded, color: Colors.red),
              label: const Text('Delete Group',
                  style: TextStyle(
                      color: Colors.red,
                      fontSize: 15,
                      fontWeight: FontWeight.bold)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.red),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _settingsLabel(String text, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.primary),
        const SizedBox(width: 6),
        Text(
          text.toUpperCase(),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: AppColors.primary,
            letterSpacing: 1.1,
          ),
        ),
      ],
    );
  }

  // -- Bottom nav item -------------------------------------------------------

  Widget _buildNavItem({
    required IconData icon,
    required String label,
    required int index,
  }) {
    final isSelected = _currentIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _currentIndex = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        padding: EdgeInsets.symmetric(
            horizontal: isSelected ? 24 : 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.white.withOpacity(0.2)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white,
                size: isSelected ? 28 : 24),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(
                    color: Colors.white,
                    fontSize: isSelected ? 12 : 10,
                    fontWeight: isSelected
                        ? FontWeight.bold
                        : FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  // -- Build -----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final screens = [
      _buildContentTab(),
      _buildMembersTab(),
      _buildStatisticsTab(),
      _buildSettingsTab(),
    ];

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: const Color(0xFF4CAF50),
        elevation: 0,
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu, color: Colors.white),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
        title: Text(
          _groupName,
          style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 20),
        ),
      ),
      drawer: AppDrawer(
        title: 'Teacher Panel',
        subtitle: _userName.isNotEmpty ? _userName : null,
        navItems: [
          ListTile(
            leading: const Icon(Icons.group, color: AppColors.primary),
            title: const Text('My Groups'),
            onTap: () {
              Navigator.pop(context); // close drawer
              Navigator.pop(context); // back to home
            },
          ),
        ],
      ),
      body: SafeArea(child: screens[_currentIndex]),
      bottomNavigationBar: Container(
        margin: const EdgeInsets.all(16),
        height: 75,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF4CAF50), Color(0xFF81C784)],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(35),
          boxShadow: [
            BoxShadow(
              color: Color(0xFF4CAF50),
              offset: const Offset(0, 8),
              blurRadius: 20,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildNavItem(
                icon: Icons.article_rounded, label: 'Content', index: 0),
            _buildNavItem(
                icon: Icons.people_rounded, label: 'Members', index: 1),
            _buildNavItem(
                icon: Icons.bar_chart_rounded,
                label: 'Statistics',
                index: 2),
            _buildNavItem(
                icon: Icons.settings_rounded, label: 'Settings', index: 3),
          ],
        ),
      ),
    );
  }
}

// -- Reusable nav card widget ------------------------------------------------

class _NavCard extends StatelessWidget {
  const _NavCard({
    required this.icon,
    required this.label,
    required this.description,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String description;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      elevation: 2,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(description,
                        style: TextStyle(
                            fontSize: 13, color: Colors.grey[600])),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.grey[400]),
            ],
          ),
        ),
      ),
    );
  }
}

// -- Assigned content section (read-only, shown in group overview) -----------

class _AssignedContentSection extends StatelessWidget {
  const _AssignedContentSection({
    required this.groupId,
    required this.groupColor,
  });

  final String groupId;
  final Color groupColor;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('personalizedContent')
          .where('status', isEqualTo: 'approved')
          .where('assignedTo', arrayContains: groupId)
          .snapshots(),
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? [];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Assigned Content',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[800],
                  ),
                ),
                if (docs.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF4CAF50).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${docs.length}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF4CAF50),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            if (docs.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Icon(Icons.folder_off_rounded,
                        size: 36, color: Colors.grey[400]),
                    const SizedBox(height: 8),
                    Text(
                      'No content assigned yet',
                      style: TextStyle(
                          fontSize: 14, color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Assign approved content from My Content in the drawer',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey[400]),
                    ),
                  ],
                ),
              )
            else
              ...docs.map((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final title = data['title'] as String? ?? 'Untitled';
                final ageGroup = data['ageGroup'] as String? ?? '';
                final initial = title.isNotEmpty
                    ? title[0].toUpperCase()
                    : '#';
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[200]!),
                  ),
                  child: ListTile(
                    leading: CircleAvatar(
                      radius: 20,
                      backgroundColor: const Color(0xFF4CAF50).withOpacity(0.12),
                      child: Text(
                        initial,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: Color(0xFF4CAF50),
                        ),
                      ),
                    ),
                    title: Text(title,
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600)),
                    subtitle: Text(ageGroup,
                        style: const TextStyle(
                            fontSize: 12, color: Colors.grey)),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'Assigned',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                    ),
                  ),
                );
              }),
          ],
        );
      },
    );
  }
}

// -- Period option widget for settings tab ----------------------------------
class _PeriodOption extends StatelessWidget {
  final int period;
  final String label;
  final String subtitle;
  final bool isSelected;
  final VoidCallback onTap;

  const _PeriodOption({
    required this.period,
    required this.label,
    required this.subtitle,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFF4CAF50)
                : Colors.grey[100],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? const Color(0xFF4CAF50)
                  : Colors.grey[300]!,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.grey[800],
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  color: isSelected
                      ? Colors.white.withOpacity(0.85)
                      : Colors.grey[600],
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}