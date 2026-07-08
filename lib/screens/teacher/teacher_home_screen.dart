// teacher_home_screen.dart
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
// import 'package:loringo_app/components/app_drawer.dart';
import 'package:loringo_app/components/responsive_scaffold.dart';
import 'package:loringo_app/screens/teacher/group_navigation_screen.dart';
import 'package:loringo_app/screens/teacher/teacher_content_screen.dart';
import 'package:loringo_app/screens/teacher/teacher_image_screen.dart';
import 'package:loringo_app/screens/teacher/teacher_league_screen.dart';
import 'package:loringo_app/screens/teacher/teacher_quizzes_screen.dart';
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
          const Divider(),
          ListTile(
            leading: const Icon(Icons.folder_rounded, color: AppColors.primary),
            title: const Text('Content'),
            onTap: () {
              if (!isWide) Navigator.pop(context);
              Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const TeacherContentScreen()));
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
            leading: const Icon(Icons.quiz_rounded, color: AppColors.primary),
            title: const Text('Quizzes'),
            onTap: () {
              if (!isWide) Navigator.pop(context);
              Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const TeacherQuizzesScreen()));
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
                      const Text('My Groups', style: AppText.h1),
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
                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return const SliverFillRemaining(child: _EmptyGroupsState());
                  }
                  final groups = snapshot.data!.docs
                    ..sort((a, b) {
                      final aTime = (a.data() as Map)['createdAt'] as Timestamp?;
                      final bTime = (b.data() as Map)['createdAt'] as Timestamp?;
                      if (aTime == null && bTime == null) return 0;
                      if (aTime == null) return 1;
                      if (bTime == null) return -1;
                      return bTime.compareTo(aTime);
                    });

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
    return _GroupCard(
      groupId: doc.id,
      name: data['name'] ?? 'Untitled',
      colorHex: data['color'] ?? '#4CAF50',
      groupCode: data['groupCode'] ?? '',
      academicYear: (data['academicYear'] as int?) ?? DateTime.now().year,
      classroom: (data['classroom'] as String?) ?? _legacyPeriodLabel(data['period']),
    );
  }
}

// Produces a readable fallback label from the old int-based 'period' field
// (1 or 2) for groups created before 'classroom' existed. Returns an empty
// string if there's nothing to fall back to, so the UI can decide how to
// display "no classroom set" rather than showing a confusing "Period null".
String _legacyPeriodLabel(dynamic period) {
  if (period == 1) return 'Period 1';
  if (period == 2) return 'Period 2';
  return '';
}

// ── Group card ────────────────────────────────────────────────────────────────

class _GroupCard extends StatelessWidget {
  final String groupId;
  final String name;
  final String colorHex;
  final String groupCode;
  final int    academicYear;
  final String classroom;

  const _GroupCard({
    required this.groupId,
    required this.name,
    required this.colorHex,
    required this.groupCode,
    required this.academicYear,
    required this.classroom,
  });

  Color get _cardColor {
    try {
      return Color(
          int.parse('FF${colorHex.replaceAll('#', '')}', radix: 16));
    } catch (_) {
      return AppColors.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _cardColor;
    return FutureBuilder<int>(
      future: _getAssignedUnitsCount(groupId),
      builder: (context, snapshot) {
        final count       = snapshot.data ?? 0;
        final contentText = count == 1 ? 'content' : 'contents';

        return GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => TeacherGroupDetailsScreen(
                groupId:   groupId,
                groupName: name,
                groupCode: groupCode,
                groupColor: color,
              ),
            ),
          ),
          child: Container(
            // margin: const EdgeInsets.only(bottom: AppSpacing.md),
            padding: const EdgeInsets.all(AppSpacing.md + 4),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [color, color.withOpacity(0.72)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(AppRadii.lg),
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.28),
                  offset: const Offset(0, 6),
                  blurRadius: 14,
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.onPrimary,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              height: 1.15,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            classroom.isNotEmpty
                                ? '$academicYear · $classroom'
                                : '$academicYear',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.82),
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Code chip
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md, vertical: AppSpacing.xs + 2),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.22),
                        borderRadius: BorderRadius.circular(AppRadii.pill),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.vpn_key_rounded,
                              color: AppColors.onPrimary, size: 13),
                          const SizedBox(width: AppSpacing.xs),
                          Text(
                            groupCode,
                            style: const TextStyle(
                              color: AppColors.onPrimary,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    const Icon(Icons.folder_rounded,
                        color: AppColors.onPrimary, size: 18),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      '$count $contentText',
                      style: const TextStyle(
                        color: AppColors.onPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const Spacer(),
                    const Icon(Icons.arrow_forward_ios_rounded,
                        color: AppColors.onPrimary, size: 16),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<int> _getAssignedUnitsCount(String groupId) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('content')
          .where('assignedTo', arrayContains: groupId)
          .get();
      return snap.docs.length;
    } catch (_) {
      return 0;
    }
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

  void _createGroup() {
    if (_formKey.currentState!.validate()) {
      final colorHex =
          '#${selectedColor.value.toRadixString(16).substring(2).toUpperCase()}';
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
                  onPressed: _createGroup,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.onPrimary,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadii.md)),
                    elevation: 0,
                  ),
                  child: const Text('Create Group',
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