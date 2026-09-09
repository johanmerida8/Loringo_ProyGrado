// archived_groups_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:loringo_app/providers/locale_provider.dart';
import 'package:loringo_app/screens/teacher/widgets/group_card.dart';
import 'package:loringo_app/screens/teacher/widgets/hierarchy_list_cards.dart';
import 'package:loringo_app/screens/teacher/widgets/teacher_screen_header.dart';
import 'package:loringo_app/theme/app_theme.dart';

/// Mirror of "My Groups" (teacher_home_screen.dart) with the archived
/// filter inverted — groups a teacher archived instead of deleting (see
/// group_navigation_screen.dart's Settings tab) land here. Opening one
/// still goes to the normal TeacherGroupDetailsScreen (via GroupCard), so
/// unarchiving is just the same Settings action in reverse.
class ArchivedGroupsScreen extends StatefulWidget {
  const ArchivedGroupsScreen({super.key});

  @override
  State<ArchivedGroupsScreen> createState() => _ArchivedGroupsScreenState();
}

class _ArchivedGroupsScreenState extends State<ArchivedGroupsScreen> {
  // Created once here rather than inline in build()'s StreamBuilder: a
  // fresh Stream<QuerySnapshot> from .snapshots() is a new object every
  // call, and StreamBuilder resubscribes (briefly dropping back to
  // ConnectionState.waiting, replacing the whole list with a spinner)
  // whenever the stream instance it's given changes — see the identical
  // fix in teacher_home_screen.dart.
  late final Stream<QuerySnapshot> _groupsStream;

  @override
  void initState() {
    super.initState();
    final teacherId = FirebaseAuth.instance.currentUser?.uid;
    _groupsStream = FirebaseFirestore.instance
        .collection('teacherGroups')
        .where('teacherId', isEqualTo: teacherId)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LocaleProvider>();

    return Scaffold(
      backgroundColor: AppColors.scaffoldBackground,
      body: Column(
        children: [
          TeacherScreenHeader(
            title: 'teacher.archived_groups_screen.title'.tr(),
            subtitle: 'teacher.archived_groups_screen.subtitle'.tr(),
            color: AppColors.primary,
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _groupsStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                      child: CircularProgressIndicator(color: AppColors.primary));
                }
                if (!snapshot.hasData) {
                  return const SizedBox.shrink();
                }

                final groups = snapshot.data!.docs
                    .where((doc) => (doc.data() as Map)['archived'] == true)
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
                  return HierarchyEmptyState(
                    icon:        Icons.archive_outlined,
                    title:       'teacher.archived_groups_screen.noArchivedGroupsTitle'
                        .tr(),
                    subtitle:    'teacher.archived_groups_screen.noArchivedGroupsSubtitle'
                        .tr(),
                    color:       AppColors.primary,
                    actionLabel: 'teacher.archived_groups_screen.backToMyGroups'.tr(),
                    onAction:    () => Navigator.pop(context),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(
                      AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.xl),
                  itemCount: groups.length,
                  itemBuilder: (context, index) {
                    final doc  = groups[index];
                    final data = doc.data() as Map<String, dynamic>;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      child: GroupCard(
                        groupId: doc.id,
                        name: data['name'] ?? 'common.untitled'.tr(),
                        colorHex: data['color'] ?? '#4CAF50',
                        academicYear:
                            (data['academicYear'] as int?) ?? DateTime.now().year,
                        classroom: (data['classroom'] as String?) ??
                            legacyPeriodLabel(data['period']),
                        isArchived: true,
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
