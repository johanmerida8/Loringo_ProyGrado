// navigation_group_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
// import 'package:loringo_app/components/app_drawer.dart';
import 'package:loringo_app/components/responsive_scaffold.dart';
import 'package:loringo_app/screens/teacher/group_details/invite_student_modal.dart';
import 'package:loringo_app/screens/teacher/student_progress_dashboard.dart';
import 'package:loringo_app/screens/teacher/teacher_activity_screen.dart';
import 'package:loringo_app/theme/app_theme.dart';

class TeacherGroupDetailsScreen extends StatefulWidget {
  final String groupId;
  final String groupName;
  final String groupCode;
  final Color  groupColor;

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

  List<Map<String, dynamic>> _students    = [];
  Map<String, dynamic>?      _teacherData;
  bool                       isLoadingMembers = false;
  late String                _groupName;
  String                     _userName = '';

  // Settings state
  final _settingsNameController = TextEditingController();
  final _settingsClassroomController = TextEditingController();
  int   _settingsYear   = DateTime.now().year;
  Color _settingsColor  = AppColors.primary;
  bool  _savingSettings = false;

  // Originals for change detection
  String _originalName      = '';
  String _originalClassroom = '';
  int    _originalYear      = DateTime.now().year;
  Color  _originalColor     = AppColors.primary;

  List<Map<String, dynamic>>? _contentItems;

  static const List<Color> _availableColors = [
    AppColors.primary,
    Color(0xFF2196F3), Color(0xFFFF9800), Color(0xFFE91E63),
    Color(0xFF9C27B0), Color(0xFFFFEB3B), Color(0xFF00BCD4),
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
    _settingsClassroomController.dispose();
    cachedProgressDashboard = null;
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
    // 'classroom' is the current field. Falls back to a readable label
    // derived from the old int-based 'period' field (1 or 2) for groups
    // created before this change, so existing groups don't suddenly show
    // a blank classroom the first time a teacher opens Settings.
    final classroom = (data['classroom'] as String?) ??
        _legacyPeriodLabel(data['period']);
    setState(() {
      _settingsNameController.text = name;
      _settingsClassroomController.text = classroom;
      _settingsYear   = year;
      _settingsColor  = parsed;
      _originalName      = name;
      _originalClassroom = classroom;
      _originalYear      = year;
      _originalColor     = parsed;
    });
  }

  static String _legacyPeriodLabel(dynamic period) {
    if (period == 1) return 'Period 1';
    if (period == 2) return 'Period 2';
    return '';
  }

  bool get _settingsHaveChanged =>
      _settingsNameController.text.trim() != _originalName ||
      _settingsClassroomController.text.trim() != _originalClassroom ||
      _settingsYear   != _originalYear ||
      _settingsColor.value != _originalColor.value;

  /// Same duplicate-name rule as group creation (see CreateGroupModal in
  /// teacher_home_screen.dart): no two groups belonging to this teacher
  /// may share a name, case-insensitive, regardless of academic year.
  /// The only difference here is scope — this group's own document must
  /// be excluded from the comparison, otherwise renaming would always
  /// "collide" with itself.
  Future<bool> _nameAlreadyExistsElsewhere(String name, String teacherId) async {
    final normalized = name.trim().toLowerCase();
    final snap = await FirebaseFirestore.instance
        .collection('teacherGroups')
        .where('teacherId', isEqualTo: teacherId)
        .get();
    return snap.docs.any((doc) {
      if (doc.id == widget.groupId) return false;
      final existingName = (doc.data()['name'] as String? ?? '').trim().toLowerCase();
      return existingName == normalized;
    });
  }

  Future<void> _saveGroupSettings() async {
    final name = _settingsNameController.text.trim();
    if (name.isEmpty) return;
    if (!_settingsHaveChanged) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('No changes made'),
        backgroundColor: Colors.grey,
      ));
      return;
    }

    final teacherId = FirebaseAuth.instance.currentUser?.uid;
    if (teacherId == null) return;

    setState(() => _savingSettings = true);

    final duplicate = await _nameAlreadyExistsElsewhere(name, teacherId);
    if (duplicate) {
      if (mounted) {
        setState(() => _savingSettings = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('You already have a group named "$name". Choose a different name.'),
          backgroundColor: AppColors.danger,
        ));
      }
      return;
    }

    final colorHex =
        '#${_settingsColor.value.toRadixString(16).substring(2).toUpperCase()}';
    try {
      await FirebaseFirestore.instance
          .collection('teacherGroups')
          .doc(widget.groupId)
          .update({
        'name':         name,
        'academicYear': _settingsYear,
        'classroom':    _settingsClassroomController.text.trim(),
        'color':        colorHex,
        // 'period' is intentionally left alone rather than deleted here —
        // if you want to fully retire it from existing documents, that
        // should be a deliberate one-off migration, not a side effect of
        // editing unrelated settings.
      });
      if (mounted) {
        setState(() {
          _groupName         = name;
          _originalName      = name;
          _originalClassroom = _settingsClassroomController.text.trim();
          _originalYear      = _settingsYear;
          _originalColor     = _settingsColor;
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Changes saved'),
          backgroundColor: AppColors.primary,
        ));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.danger));
    } finally {
      if (mounted) setState(() => _savingSettings = false);
    }
  }

  Future<void> _deleteGroup() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.md)),
        title: const Text('Delete Group'),
        content: Text('Delete "$_groupName"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: AppColors.onPrimary,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadii.sm)),
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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.danger));
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

  Future<void> _loadGroupMembers() async {
    setState(() => isLoadingMembers = true);
    try {
      final groupDoc = await FirebaseFirestore.instance
          .collection('teacherGroups')
          .doc(widget.groupId)
          .get();
      if (groupDoc.exists) {
        final teacherDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(groupDoc.data()!['teacherId'])
            .get();
        if (teacherDoc.exists) _teacherData = teacherDoc.data();
      }

      final studentsSnapshot = await FirebaseFirestore.instance
          .collection('students')
          .where('groupId', isEqualTo: widget.groupId)
          .get();

      final studentsList = <Map<String, dynamic>>[];
      for (var doc in studentsSnapshot.docs) {
        final data     = doc.data();
        final parentId = data['parentId'];
        String parentEmail = '';
        if (parentId != null) {
          final parentDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(parentId)
              .get();
          if (parentDoc.exists) {
            parentEmail = parentDoc.data()?['email'] ?? '';
          }
        }
        studentsList.add({
          'id':          doc.id,
          'name':        data['names'] ?? 'No name',
          'avatar':      data['avatar'] ?? '',
          'accessCode':  data['accessCode'] ?? '',
          'parentId':    parentId ?? '',
          'parentEmail': parentEmail,
          'joinedAt':    data['createdAt'],
        });
      }
      studentsList.sort((a, b) =>
          (a['name'] as String).compareTo(b['name']));
      setState(() {
        _students        = studentsList;
        isLoadingMembers = false;
      });
    } catch (e) {
      setState(() {
        _students        = [];
        isLoadingMembers = false;
      });
    }
  }

  void _copyCodeToClipboard() {
    Clipboard.setData(ClipboardData(text: widget.groupCode));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Code copied to clipboard'),
      backgroundColor: AppColors.primary,
      duration: Duration(seconds: 2),
    ));
  }

  Future<void> _removeStudent(String studentId, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Student'),
        content: Text('Remove $name from the group?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await FirebaseFirestore.instance
          .collection('students')
          .doc(studentId)
          .update({'groupId': FieldValue.delete(), 'lastUpdate': FieldValue.serverTimestamp()});
      await FirebaseFirestore.instance
          .collection('teacherGroups')
          .doc(widget.groupId)
          .collection('students')
          .doc(studentId)
          .delete();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Student removed from group'),
          backgroundColor: Colors.orange,
        ));
        _loadGroupMembers();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.danger));
    }
  }

  void _showInviteStudentModal() {
    showInviteStudentModal(
      context: context,
      groupId: widget.groupId,
      groupName: widget.groupName,
      groupCode: widget.groupCode,
      groupColor: widget.groupColor,
    );
  }

  // ── Tab builders ──────────────────────────────────────────────────────────

  Widget _buildContentTab() {
    return Stack(
      children: [
        TeacherActivityScreen(
          groupId:        widget.groupId,
          groupName:      widget.groupName,
          embedded:       true,
          onLoaded:       (items) => _contentItems = items,
          preloadedItems: _contentItems,
        ),
        // Full Screen button — top-right floating pill
        Positioned(
          top: AppSpacing.sm,
          right: AppSpacing.sm,
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppRadii.pill),
            elevation: 3,
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadii.pill),
              onTap: () => _pushWithTransition(TeacherActivityScreen(
                groupId:        widget.groupId,
                groupName:      widget.groupName,
                embedded:       false,
                preloadedItems: _contentItems,
              )),
              child: const Padding(
                padding: EdgeInsets.symmetric(
                    horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.fullscreen_rounded,
                      color: AppColors.primary, size: 20),
                  SizedBox(width: 4),
                  Text('Full Screen',
                      style: TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      )),
                ]),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMembersTab() {
    if (isLoadingMembers) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.primary));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionLabel('Teacher'),
          const SizedBox(height: AppSpacing.md),

          // Teacher card
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppRadii.lg),
              boxShadow: _cardShadow,
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.all(AppSpacing.md),
              leading: CircleAvatar(
                backgroundColor: AppColors.primarySoft(0.15),
                radius: 28,
                child: const Icon(Icons.school_rounded,
                    color: AppColors.primary, size: 26),
              ),
              title: Text(
                _teacherData?['name'] ?? 'Teacher',
                style: AppText.cardTitle.copyWith(fontSize: 16),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_teacherData?['email'] ?? '', style: AppText.caption),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.primarySoft(0.12),
                      borderRadius: BorderRadius.circular(AppRadii.sm),
                    ),
                    child: const Text('Group Owner',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        )),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: AppSpacing.xl),

          // Students header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _SectionLabel('Students (${_students.length})'),
              GestureDetector(
                onTap: _showInviteStudentModal,
                child: Container(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft(0.1),
                    borderRadius: BorderRadius.circular(AppRadii.md),
                  ),
                  child: const Icon(Icons.person_add_rounded,
                      color: AppColors.primary, size: 22),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),

          if (_students.isEmpty)
            _EmptyMembers()
          else
            ...List.generate(_students.length, (i) {
              final s           = _students[i];
              final name        = s['name']        as String;
              final parentEmail = s['parentEmail'] as String;
              final avatar      = s['avatar']      as String;
              return Container(
                margin: const EdgeInsets.only(bottom: AppSpacing.md),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(AppRadii.lg),
                  boxShadow: _cardShadow,
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(AppSpacing.md),
                  leading: CircleAvatar(
                    backgroundColor: AppColors.primarySoft(0.15),
                    radius: 26,
                    backgroundImage:
                        avatar.isNotEmpty ? AssetImage(avatar) : null,
                    child: avatar.isEmpty
                        ? Text(
                            name.isNotEmpty ? name[0].toUpperCase() : '?',
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ))
                        : null,
                  ),
                  title: Text(name,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.bold)),
                  subtitle: Text(
                    parentEmail.isNotEmpty
                        ? 'Parent: $parentEmail'
                        : 'No parent email',
                    style: AppText.caption,
                  ),
                  trailing: GestureDetector(
                    onTap: () => _removeStudent(s['id'], name),
                    child: Container(
                      padding: const EdgeInsets.all(AppSpacing.sm - 2),
                      decoration: BoxDecoration(
                        color: AppColors.danger.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(AppRadii.sm),
                      ),
                      child: Icon(Icons.remove_circle_outline,
                          color: AppColors.danger, size: 20),
                    ),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  StudentProgressDashboard? cachedProgressDashboard;

  Widget _buildStatisticsTab() {
    if (isLoadingMembers) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.primary));
    }
    cachedProgressDashboard ??= StudentProgressDashboard(
      groupId:   widget.groupId,
      groupName: widget.groupName,
      students:  _students,
      showAppBar: false,
    );
    return cachedProgressDashboard!;
  }

  Widget _buildSettingsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Group Settings', style: AppText.h1),
          const SizedBox(height: AppSpacing.lg),

          // Group name
          _SettingsLabel('Group Name', Icons.group_outlined),
          const SizedBox(height: AppSpacing.sm),
          TextFormField(
            controller: _settingsNameController,
            textCapitalization: TextCapitalization.words,
            decoration: _settingsInputDecoration('Enter group name'),
          ),
          const SizedBox(height: AppSpacing.lg),

          // Academic year
          _SettingsLabel('Academic Year', Icons.calendar_today_outlined),
          const SizedBox(height: AppSpacing.sm),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _years.map((year) {
                final selected = year == _settingsYear;
                return GestureDetector(
                  onTap: () => setState(() => _settingsYear = year),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: const EdgeInsets.only(right: AppSpacing.sm),
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md + 4, vertical: AppSpacing.md - 4),
                    decoration: BoxDecoration(
                      color: selected ? AppColors.primary : Colors.white,
                      borderRadius: BorderRadius.circular(AppRadii.md),
                      border: Border.all(
                        color: selected ? AppColors.primary : AppColors.divider,
                        width: selected ? 2 : 1,
                      ),
                    ),
                    child: Text(
                      '$year',
                      style: TextStyle(
                        color:      selected ? AppColors.onPrimary : Colors.grey[700],
                        fontWeight: FontWeight.bold,
                        fontSize:   14,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // Classroom (free text identifier — replaces the old fixed
          // Period 1/2 date-range selector)
          _SettingsLabel('Classroom', Icons.meeting_room_outlined),
          const SizedBox(height: AppSpacing.sm),
          TextFormField(
            controller: _settingsClassroomController,
            textCapitalization: TextCapitalization.words,
            decoration: _settingsInputDecoration('e.g. Aula 3, Room B'),
          ),
          const SizedBox(height: AppSpacing.lg),

          // Color
          _SettingsLabel('Group Color', Icons.palette_outlined),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.md,
            children: _availableColors.map((color) {
              final selected = color.value == _settingsColor.value;
              return GestureDetector(
                onTap: () => setState(() => _settingsColor = color),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: color, shape: BoxShape.circle,
                    border: Border.all(
                      color: selected ? Colors.black45 : Colors.transparent,
                      width: 3,
                    ),
                    boxShadow: selected
                        ? [BoxShadow(color: color.withOpacity(0.5),
                            blurRadius: 8, spreadRadius: 1)]
                        : [],
                  ),
                  child: selected
                      ? const Icon(Icons.check, color: Colors.white, size: 20)
                      : null,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: AppSpacing.xl),

          // Save
          SizedBox(
            width: double.infinity, height: 50,
            child: ElevatedButton(
              onPressed: _savingSettings ? null : _saveGroupSettings,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.onPrimary,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadii.md)),
                elevation: 0,
              ),
              child: _savingSettings
                  ? const SizedBox(
                      width: 22, height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.onPrimary))
                  : const Text('Save Changes',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // Danger zone
          const Divider(),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            width: double.infinity, height: 50,
            child: OutlinedButton.icon(
              onPressed: _deleteGroup,
              icon: Icon(Icons.delete_rounded, color: AppColors.danger),
              label: Text('Delete Group',
                  style: TextStyle(
                    color: AppColors.danger,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  )),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: AppColors.danger),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadii.md)),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }

  InputDecoration _settingsInputDecoration(String hint) => InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.md - 2),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadii.md),
            borderSide: BorderSide(color: AppColors.divider)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadii.md),
            borderSide: BorderSide(color: AppColors.divider)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadii.md),
            borderSide: const BorderSide(color: AppColors.primary, width: 2)),
      );

  // ── Bottom nav item ───────────────────────────────────────────────────────

  Widget _buildNavItem({
    required IconData icon,
    required String   label,
    required int      index,
  }) {
    final isSelected = _currentIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _currentIndex = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        padding: EdgeInsets.symmetric(
            horizontal: isSelected ? 22 : 14, vertical: AppSpacing.md - 4),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white.withOpacity(0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadii.pill),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppColors.onPrimary,
                size: isSelected ? 26 : 22),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(
                  color: AppColors.onPrimary,
                  fontSize: isSelected ? 12 : 10,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                )),
          ],
        ),
      ),
    );
  }

  Future<T?> _pushWithTransition<T>(Widget page) {
    return Navigator.push<T>(
      context,
      PageRouteBuilder(
        pageBuilder: (_, animation, __) => page,
        transitionsBuilder: (_, animation, __, child) {
          final slide = Tween(
            begin: const Offset(0.0, 0.05), end: Offset.zero,
          ).chain(CurveTween(curve: Curves.easeInOutCubic)).animate(animation);
          final fade = Tween<double>(begin: 0, end: 1)
              .animate(CurvedAnimation(parent: animation, curve: Curves.easeIn));
          return FadeTransition(
              opacity: fade,
              child: SlideTransition(position: slide, child: child));
        },
        transitionDuration: const Duration(milliseconds: 400),
        reverseTransitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      _buildContentTab(),
      _buildMembersTab(),
      _buildStatisticsTab(),
      _buildSettingsTab(),
    ];
    const tabLabels = ['Content', 'Members', 'Statistics', 'Settings'];
    const tabIcons = [
      Icons.article_rounded,
      Icons.people_rounded,
      Icons.bar_chart_rounded,
      Icons.settings_rounded,
    ];

    return ResponsiveScaffold(
      headerIcon: Icons.school,
      drawerTitle: _groupName,
      drawerSubtitle: _userName.isNotEmpty ? _userName : null,
      hideBottomNavOnWide: true,
      navItemsBuilder: (context, isWide) => [
        ListTile(
          leading: const Icon(Icons.group, color: AppColors.primary),
          title: const Text('My Groups'),
          onTap: () {
            if (!isWide) Navigator.pop(context);
            Navigator.pop(context);
          },
        ),
        const Divider(),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
          child: Row(children: [
            Icon(Icons.dashboard, size: 16, color: AppColors.primary),
            const SizedBox(width: 6),
            Text('GROUP', style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.bold,
                color: AppColors.primary, letterSpacing: 1)),
          ]),
        ),
        for (var i = 0; i < tabLabels.length; i++)
          ListTile(
            leading: Icon(tabIcons[i], color: AppColors.primary),
            title: Text(tabLabels[i]),
            selected: _currentIndex == i,
            selectedTileColor: AppColors.primarySoft(0.08),
            trailing: _currentIndex == i
                ? const Icon(Icons.check_circle, color: AppColors.primary)
                : null,
            onTap: () {
              setState(() => _currentIndex = i);
              if (!isWide && Navigator.canPop(context)) Navigator.pop(context);
            },
          ),
      ],
      // Bottom nav is still built (for narrow/mobile); ResponsiveScaffold
      // hides it automatically once isWide is true.
      bottomNavigationBar: Container(
        margin: const EdgeInsets.all(AppSpacing.md),
        height: 75,
        decoration: BoxDecoration(
          gradient: AppDecorations.primaryGradient,
          borderRadius: BorderRadius.circular(AppRadii.pill),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withOpacity(0.35),
              offset: const Offset(0, 8),
              blurRadius: 20,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildNavItem(icon: Icons.article_rounded, label: 'Content', index: 0),
            _buildNavItem(icon: Icons.people_rounded, label: 'Members', index: 1),
            _buildNavItem(icon: Icons.bar_chart_rounded, label: 'Statistics', index: 2),
            _buildNavItem(icon: Icons.settings_rounded, label: 'Settings', index: 3),
          ],
        ),
      ),
      bodyBuilder: (context, isWide) => Builder(
        builder: (ctx) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.sm),
              child: Row(
                children: [
                  if (!isWide)
                    GestureDetector(
                      onTap: () => Scaffold.of(ctx).openDrawer(),
                      child: Container(
                        padding: const EdgeInsets.all(AppSpacing.sm),
                        decoration: BoxDecoration(
                          color: AppColors.primarySoft(0.1),
                          borderRadius: BorderRadius.circular(AppRadii.md),
                        ),
                        child: const Icon(Icons.menu_rounded,
                            color: AppColors.primary, size: 22),
                      ),
                    ),
                  if (!isWide) const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_groupName, style: AppText.h1),
                        Text(
                          tabLabels[_currentIndex],
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: screens[_currentIndex]),
          ],
        ),
      ),
    );
  }
}

// ── Shared helpers ────────────────────────────────────────────────────────────

List<BoxShadow> get _cardShadow => [
  BoxShadow(
    color: Colors.black.withOpacity(0.05),
    blurRadius: 10,
    offset: const Offset(0, 3),
  ),
];

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(text,
      style: AppText.h1.copyWith(fontSize: 18));
}

class _SettingsLabel extends StatelessWidget {
  final String  text;
  final IconData icon;
  const _SettingsLabel(this.text, this.icon);

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon, size: 15, color: AppColors.primary),
          const SizedBox(width: 6),
          Text(
            text.toUpperCase(),
            style: const TextStyle(
              fontSize: 11, fontWeight: FontWeight.bold,
              color: AppColors.primary, letterSpacing: 1.1,
            ),
          ),
        ],
      );
}

class _EmptyMembers extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            children: [
              Icon(Icons.people_outline_rounded,
                  size: 72, color: AppColors.divider),
              const SizedBox(height: AppSpacing.md),
              Text('No students yet',
                  style: AppText.subtitle.copyWith(
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: AppSpacing.sm),
              Text('Tap + to invite students', style: AppText.caption),
            ],
          ),
        ),
      );
}