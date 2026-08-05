// teacher_home_screen.dart
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
// import 'package:loringo_app/components/app_drawer.dart';
import 'package:loringo_app/components/notifications_badge.dart';
import 'package:loringo_app/components/responsive_scaffold.dart';
import 'package:loringo_app/screens/parent/parent_notifications_screen.dart';
import 'package:loringo_app/screens/teacher/teacher_content_editor_screen.dart';
import 'package:loringo_app/screens/teacher/teacher_image_screen.dart';
import 'package:loringo_app/screens/teacher/archived_groups_screen.dart';
import 'package:loringo_app/screens/teacher/teacher_league_screen.dart';
import 'package:loringo_app/screens/teacher/widgets/group_card.dart';
import 'package:loringo_app/services/auth/auth_gate.dart';
import 'package:loringo_app/services/auth/biometric_service.dart';
import 'package:loringo_app/theme/app_theme.dart';
import 'package:loringo_app/widget/secured_screen.dart';

class TeacherHomeScreen extends StatefulWidget {
  const TeacherHomeScreen({super.key});

  @override
  State<TeacherHomeScreen> createState() => _TeacherHomeScreenState();
}

class _TeacherHomeScreenState extends State<TeacherHomeScreen>
    with WidgetsBindingObserver {
  String _userName = '';
  bool _wasInBackground = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadUserName();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _wasInBackground = true;
    } else if (state == AppLifecycleState.resumed && _wasInBackground) {
      _wasInBackground = false;
      _checkBiometricOnResume();
    }
  }

  Future<void> _checkBiometricOnResume() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final enabled = await BiometricService.isBiometricEnabled(uid);
    if (!enabled) return;
    final authenticated = await BiometricService.authenticate(
      reason: 'Verify your identity to continue',
    );
    if (!authenticated && mounted) {
      await FirebaseAuth.instance.signOut();
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthGate()),
        (route) => false,
      );
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

  Future<void> _showCreateGroupModal() async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const CreateGroupModal(),
    ).then((newGroupData) async {
      if (newGroupData == null) return;
      final teacherId = FirebaseAuth.instance.currentUser?.uid;
      if (teacherId == null) return;
      try {
        await FirebaseFirestore.instance.collection('teacherGroups').add({
          'name':         newGroupData['name'],
          'color':        newGroupData['color'],
          'groupCode':    newGroupData['groupCode'],
          'academicYear': newGroupData['academicYear'],
          'classroom':    newGroupData['classroom'],
          'teacherId':    teacherId,
          'archived':     false,
          'createdAt':    FieldValue.serverTimestamp(),
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Group created! Code: ${newGroupData['groupCode']}'),
            backgroundColor: AppColors.primary,
            duration: const Duration(seconds: 3),
          ));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Error creating group: $e'),
            backgroundColor: AppColors.danger,
          ));
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final teacherId = FirebaseAuth.instance.currentUser?.uid;

    return SecuredScreen(
      child: ResponsiveScaffold(
        headerIcon: Icons.school,
        drawerTitle: 'Teacher Panel',
        drawerSubtitle: _userName.isNotEmpty ? _userName : null,
        navItemsBuilder: (context, isWide) => [
          ListTile(
            leading: const Icon(Icons.group, color: AppColors.primary),
            title: const Text('My Groups'),
            selected: true,
            selectedTileColor: AppColors.primarySoft(0.08),
            onTap: () {
              if (!isWide) Navigator.pop(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.archive_rounded, color: AppColors.primary),
            title: const Text('Archived Groups'),
            onTap: () {
              if (!isWide) Navigator.pop(context);
              Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const ArchivedGroupsScreen()));
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.folder_rounded, color: AppColors.primary),
            title: const Text('Content'),
            onTap: () {
              if (!isWide) Navigator.pop(context);
              Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const TeacherContentEditorScreen()));
            },
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_rounded, color: AppColors.primary),
            title: const Text('Media Library'),
            onTap: () {
              if (!isWide) Navigator.pop(context);
              Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const TeacherImageScreen()));
            },
          ),
          ListTile(
            leading: const Icon(Icons.emoji_events_rounded, color: AppColors.primary),
            title: const Text('League & Ranking'),
            onTap: () {
              if (!isWide) Navigator.pop(context);
              Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const TeacherLeagueScreen()));
            },
          ),
        ],
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _showCreateGroupModal,
          backgroundColor: AppColors.primary,
          elevation: 3,
          icon: const Icon(Icons.add, color: AppColors.onPrimary),
          label: const Text(
            'Create Group',
            style: TextStyle(color: AppColors.onPrimary, fontWeight: FontWeight.bold),
          ),
        ),
        bodyBuilder: (context, isWide) => Builder(
          builder: (ctx) => CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
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
                      const Expanded(child: Text('My Groups', style: AppText.h1)),
                      // NotificationBadge is role-agnostic (streams
                      // `notifications` by userId, not by role), so the
                      // same component the parent dashboard uses works
                      // here unmodified — teachers now receive overdue-
                      // activity alerts (notifyOverdueActivities Cloud
                      // Function) that need somewhere to surface.
                      NotificationBadge(
                        userId: teacherId ?? '',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const ParentNotificationsScreen()),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('teacherGroups')
                    .where('teacherId', isEqualTo: teacherId)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const SliverFillRemaining(
                      child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
                    );
                  }
                  if (snapshot.hasError) {
                    return SliverFillRemaining(child: _ErrorState(onRetry: () => setState(() {})));
                  }
                  if (!snapshot.hasData) {
                    return const SliverFillRemaining(child: _EmptyGroupsState());
                  }
                  // Archived groups never show up here — they only live in
                  // "Archived Groups" (see the drawer entry above). Missing
                  // 'archived' (groups created before this field existed)
                  // is treated as not-archived, so nothing needs a
                  // migration.
                  final groups = snapshot.data!.docs
                      .where((doc) => (doc.data() as Map)['archived'] != true)
                      .toList()
                    ..sort((a, b) {
                      final aTime = (a.data() as Map)['createdAt'] as Timestamp?;
                      final bTime = (b.data() as Map)['createdAt'] as Timestamp?;
                      if (aTime == null && bTime == null) return 0;
                      if (aTime == null) return 1;
                      if (bTime == null) return -1;
                      return bTime.compareTo(aTime);
                    });

                  if (groups.isEmpty) {
                    return const SliverFillRemaining(child: _EmptyGroupsState());
                  }

                  return SliverPadding(
                    padding: const EdgeInsets.fromLTRB(
                        AppSpacing.md, AppSpacing.sm, AppSpacing.md, 100),
                    sliver: isWide
                        ? SliverGrid(
                            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 420,
                              mainAxisSpacing: AppSpacing.md,
                              crossAxisSpacing: AppSpacing.md,
                              mainAxisExtent: 150,
                            ),
                            delegate: SliverChildBuilderDelegate(
                              (context, index) => _buildGroupCard(groups[index]),
                              childCount: groups.length,
                            ),
                          )
                        : SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) => Padding(
                                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                                child: _buildGroupCard(groups[index]),
                              ),
                              childCount: groups.length,
                            ),
                          ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGroupCard(QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return GroupCard(
      groupId: doc.id,
      name: data['name'] ?? 'Untitled',
      colorHex: data['color'] ?? '#4CAF50',
      groupCode: data['groupCode'] ?? '',
      academicYear: (data['academicYear'] as int?) ?? DateTime.now().year,
      classroom: (data['classroom'] as String?) ?? legacyPeriodLabel(data['period']),
    );
  }
}

// ── Empty / Error states ──────────────────────────────────────────────────────

class _EmptyGroupsState extends StatelessWidget {
  const _EmptyGroupsState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.school_rounded, size: 80, color: AppColors.divider),
          const SizedBox(height: AppSpacing.md),
          Text('No groups yet',
              style: AppText.subtitle.copyWith(
                  fontSize: 18, fontWeight: FontWeight.w500)),
          const SizedBox(height: AppSpacing.sm),
          Text('Tap + to create your first group',
              style: AppText.caption.copyWith(fontSize: 14)),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline_rounded,
              size: 60, color: AppColors.danger),
          const SizedBox(height: AppSpacing.md),
          const Text('Something went wrong', style: AppText.body),
          const SizedBox(height: AppSpacing.md),
          ElevatedButton.icon(
            onPressed: onRetry,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.onPrimary,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadii.md)),
            ),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

// ── Create Group Modal ────────────────────────────────────────────────────────

class CreateGroupModal extends StatefulWidget {
  const CreateGroupModal({super.key});

  @override
  State<CreateGroupModal> createState() => _CreateGroupModalState();
}

class _CreateGroupModalState extends State<CreateGroupModal> {
  final _formKey        = GlobalKey<FormState>();
  final nameController  = TextEditingController();
  final classroomController = TextEditingController();
  Color selectedColor   = AppColors.primary;
  int   selectedYear    = DateTime.now().year;
  bool  _isChecking     = false;

  List<int> get _years {
    final current = DateTime.now().year;
    return List.generate(5, (i) => current + i);
  }

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

  String _generateGroupCode() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random();
    return List.generate(6, (_) => chars[random.nextInt(chars.length)]).join();
  }

  /// Checks whether this teacher already has a group with the same name
  /// (case-insensitive, trimmed), regardless of academic year — the
  /// scope is global per teacher, not per-year, since the same title
  /// showing up twice across any two groups is what actually causes
  /// confusion when assigning content later.
  ///
  /// Firestore can't do a case-insensitive query directly, so this reads
  /// all of the teacher's groups and compares client-side. That's fine
  /// at the scale a single teacher's group list realistically reaches;
  /// if that ever changes, a stored lowercase 'nameLower' field with an
  /// exact-match query would be the way to avoid the full read.
  Future<bool> _nameAlreadyExists(String name, String teacherId) async {
    final normalized = name.trim().toLowerCase();
    final snap = await FirebaseFirestore.instance
        .collection('teacherGroups')
        .where('teacherId', isEqualTo: teacherId)
        .get();
    return snap.docs.any((doc) {
      final existingName = (doc.data()['name'] as String? ?? '').trim().toLowerCase();
      return existingName == normalized;
    });
  }

  Future<void> _createGroup() async {
    if (!_formKey.currentState!.validate()) return;

    final teacherId = FirebaseAuth.instance.currentUser?.uid;
    if (teacherId == null) return;

    setState(() => _isChecking = true);
    final duplicate = await _nameAlreadyExists(nameController.text, teacherId);
    if (mounted) setState(() => _isChecking = false);

    if (duplicate) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('You already have a group named "${nameController.text.trim()}". Choose a different name.'),
          backgroundColor: AppColors.danger,
        ));
      }
      return;
    }

    final colorHex =
        '#${selectedColor.value.toRadixString(16).substring(2).toUpperCase()}';
    if (mounted) {
      Navigator.pop(context, {
        'name':         nameController.text.trim(),
        'color':        colorHex,
        'groupCode':    _generateGroupCode(),
        'academicYear': selectedYear,
        'classroom':    classroomController.text.trim(),
      });
    }
  }

  @override
  void dispose() {
    nameController.dispose();
    classroomController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadii.lg + 6)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 36, height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Create New Group', style: AppText.h1),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                    color: AppColors.muted,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),

              // Name field
              _ModalLabel('Group Name', Icons.group_outlined),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: nameController,
                textCapitalization: TextCapitalization.words,
                decoration: _inputDecoration('e.g. Grade 1 – Morning'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Enter a group name' : null,
              ),
              const SizedBox(height: AppSpacing.lg),

              // Academic year
              _ModalLabel('Academic Year', Icons.calendar_today_outlined),
              const SizedBox(height: AppSpacing.sm),
              _ChipRow<int>(
                items:         _years,
                selected:      selectedYear,
                label:         (y) => '$y',
                onSelected:    (y) => setState(() => selectedYear = y),
                selectedColor: AppColors.primary,
              ),
              const SizedBox(height: AppSpacing.lg),

              // Classroom (free text identifier — replaces the old fixed
              // Period 1/2 date-range selector)
              _ModalLabel('Classroom', Icons.meeting_room_outlined),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: classroomController,
                textCapitalization: TextCapitalization.words,
                decoration: _inputDecoration('e.g. Aula 3, Room B'),
              ),
              const SizedBox(height: AppSpacing.lg),

              // Color
              _ModalLabel('Group Color', Icons.palette_outlined),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.md,
                children: _availableColors.map((color) {
                  final sel = color.value == selectedColor.value;
                  return GestureDetector(
                    onTap: () => setState(() => selectedColor = color),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: 44, height: 44,
                      decoration: BoxDecoration(
                        color: color, shape: BoxShape.circle,
                        border: Border.all(
                          color: sel ? Colors.black45 : Colors.transparent,
                          width: 3,
                        ),
                        boxShadow: sel
                            ? [BoxShadow(color: color.withOpacity(0.5),
                                blurRadius: 8, spreadRadius: 1)]
                            : [],
                      ),
                      child: sel ? const Icon(Icons.check, color: Colors.white, size: 20) : null,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: AppSpacing.xl),

              // Submit
              SizedBox(
                width: double.infinity, height: 52,
                child: ElevatedButton(
                  onPressed: _isChecking ? null : _createGroup,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.onPrimary,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadii.md)),
                    elevation: 0,
                  ),
                  child: _isChecking
                      ? const SizedBox(
                          height: 22, width: 22,
                          child: CircularProgressIndicator(
                              color: AppColors.onPrimary, strokeWidth: 2),
                        )
                      : const Text('Create Group',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) => InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: AppColors.scaffoldBackground,
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
}

// ── Shared modal helpers ──────────────────────────────────────────────────────

class _ModalLabel extends StatelessWidget {
  final String  text;
  final IconData icon;
  const _ModalLabel(this.text, this.icon);

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

class _ChipRow<T> extends StatelessWidget {
  final List<T>        items;
  final T              selected;
  final String Function(T) label;
  final ValueChanged<T> onSelected;
  final Color          selectedColor;

  const _ChipRow({
    required this.items,
    required this.selected,
    required this.label,
    required this.onSelected,
    required this.selectedColor,
  });

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: items.map((item) {
            final isSel = item == selected;
            return GestureDetector(
              onTap: () => onSelected(item),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                margin: const EdgeInsets.only(right: AppSpacing.sm),
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md + 4, vertical: AppSpacing.sm + 4),
                decoration: BoxDecoration(
                  color: isSel ? selectedColor : Colors.white,
                  borderRadius: BorderRadius.circular(AppRadii.md),
                  border: Border.all(
                    color: isSel ? selectedColor : AppColors.divider,
                    width: isSel ? 2 : 1,
                  ),
                ),
                child: Text(
                  label(item),
                  style: TextStyle(
                    color: isSel ? AppColors.onPrimary : Colors.grey[700],
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      );
}