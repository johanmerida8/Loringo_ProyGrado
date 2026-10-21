import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:loringo_app/components/app_loading_indicator.dart';
import 'package:loringo_app/providers/locale_provider.dart';
import 'package:loringo_app/screens/teacher/content/teacher_content_structure_screen.dart';
import 'package:loringo_app/screens/teacher/content/create_content_screen.dart';
import 'package:loringo_app/screens/teacher/widgets/teacher_confirm_dialog.dart';
import 'package:loringo_app/screens/teacher/widgets/teacher_screen_header.dart';
import 'package:loringo_app/services/content/content_assignment_guard.dart';
import 'package:loringo_app/services/database/database.dart';
import 'package:loringo_app/theme/app_theme.dart';

// Backward-compat resolver: content docs written before the active/archived
// status field existed only have the old `archived: bool` field, and a
// handful of docs from this session's brief 'draft' experiment may still
// carry `status: 'draft'` -- both fall back to 'active' here rather than a
// dead-end value nothing filters for anymore, so nothing goes missing from
// both remaining filters.
String contentStatus(Map<String, dynamic> data) {
  if (data['status'] == 'archived') return 'archived';
  if (data['archived'] == true) return 'archived';
  return 'active';
}

// ── TeacherContentEditorScreen ─────────────────────────────────────────────
// Lista de todos los contenidos del docente, sin estados de aprobación
//
// NOTE: this screen previously had its own Scaffold.appBar (a solid green
// bar) plus a separate colored stats strip below it. Both are removed here
// to match the flat, no-AppBar look applied across the rest of the content
// hierarchy (Unit/Lesson/Activity/Task editor screens) — this is the entry
// point of that hierarchy, so it needs the same treatment, not an
// exception. TeacherScreenHeader replaces the AppBar; the "N Total
// Content" badge that used to live inside the green strip now sits as a
// plain inline chip directly under the header, on the scaffold background.
//
// ASSIGNMENT: a content item can be assigned to any number of groups at
// once, via the "Assign to Groups" action below (see _AssignSheet) --
// there is no single "owning" group. Assigning/unassigning writes to the
// `assignedTo` array (Database.shareContentWithGroup/
// unshareContentFromGroup), gated by ContentAssignmentGuard: a group
// can't be unassigned once its students have recorded progress against
// this content (see content_assignment_guard.dart).

class TeacherContentEditorScreen extends StatelessWidget {
  const TeacherContentEditorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final teacherId = FirebaseAuth.instance.currentUser?.uid;
    if (teacherId == null) {
      return const Scaffold(body: Center(child: Text('Not authenticated')));
    }
    return _Body(teacherId: teacherId);
  }
}

class _Body extends StatefulWidget {
  const _Body({required this.teacherId});
  final String teacherId;

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  static const Color _green = AppColors.primary;

  @override
  Widget build(BuildContext context) {
    context.watch<LocaleProvider>();
    return Scaffold(
      backgroundColor: AppColors.scaffoldBackground,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: _green,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: Text(
          'teacher.teacher_content_editor_screen.newContent'.tr(),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const CreatePersonalizedContentScreen(),
          ),
        ),
      ),
      body: Column(
        children: [
          TeacherScreenHeader(
            title: 'teacher.teacher_content_editor_screen.title'.tr(),
            color: _green,
            trailing: TeacherHeaderIconButton(
              icon: Icons.archive_outlined,
              color: _green,
              tooltip: 'teacher.teacher_content_editor_screen.archivedTooltip'.tr(),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => _ArchivedContentScreen(teacherId: widget.teacherId),
                ),
              ),
            ),
          ),
          Expanded(
            child: _ContentListView(teacherId: widget.teacherId, status: 'active'),
          ),
        ],
      ),
    );
  }
}

// ── Archived content screen ─────────────────────────────────────────────
// Reached from Mi Contenido's header archive icon. Reuses the exact same
// list rendering (_ContentListView) and archive business rules as the main
// screen -- just fixed to status: 'archived' and given its own back-
// navigable screen instead of an in-place filter chip.
class _ArchivedContentScreen extends StatelessWidget {
  const _ArchivedContentScreen({required this.teacherId});
  final String teacherId;

  static const Color _green = AppColors.primary;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBackground,
      body: Column(
        children: [
          TeacherScreenHeader(
            title: 'teacher.teacher_content_editor_screen.archivedScreenTitle'.tr(),
            color: _green,
          ),
          Expanded(
            child: _ContentListView(teacherId: teacherId, status: 'archived'),
          ),
        ],
      ),
    );
  }
}

// ── Content list (shared by the main and archived screens) ─────────────

class _ContentListView extends StatelessWidget {
  const _ContentListView({required this.teacherId, required this.status});
  final String teacherId;
  final String status;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: Database().getTeacherContentStream(teacherId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const AppLoadingIndicator();
        }
        final allDocs = snapshot.data?.docs ?? [];

        if (allDocs.isEmpty) {
          return _EmptyState(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const CreatePersonalizedContentScreen(),
              ),
            ),
          );
        }

        final docs = allDocs.where((d) {
          return contentStatus(d.data() as Map<String, dynamic>) == status;
        }).toList();

        if (docs.isEmpty) {
          return _FilteredEmptyState(status: status);
        }

        return CustomScrollView(
          slivers: [
            // ── Content list ──────────────────
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate((context, index) {
                  final doc = docs[index];
                  return _ContentCard(doc: doc, teacherId: teacherId);
                }, childCount: docs.length),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ── Content card ──────────────────────────────────────────────────────────────

class _ContentCard extends StatelessWidget {
  const _ContentCard({required this.doc, required this.teacherId});
  final QueryDocumentSnapshot doc;
  final String teacherId;

  static const Color _green = AppColors.primary;

  @override
  Widget build(BuildContext context) {
    final data = doc.data() as Map<String, dynamic>;
    final title = data['title'] as String? ?? 'common.untitled'.tr();
    final ageGroup = data['ageGroup'] as String? ?? '';
    final desc = data['description'] as String? ?? '';
    final assignedTo =
        (data['assignedTo'] as List?)?.cast<String>() ?? const [];
    final status = contentStatus(data);
    final initial = title.isNotEmpty ? title[0].toUpperCase() : '#';

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TeacherContentStructureScreen(
            groupId: '',
            contentId: doc.id,
            contentTitle: title,
            groupColor: _green,
          ),
        ),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border(left: BorderSide(color: _green, width: 4)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Top row ──────────────────────────────────────────────────
              Row(
                children: [
                  // Avatar
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: _green.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        initial,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          color: _green,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Icon(
                              Icons.cake_outlined,
                              size: 12,
                              color: Colors.grey.shade400,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              ageGroup,
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Actions menu
                  // Organized as: primary actions (Edit) up top, then a
                  // divider, then lifecycle/destructive actions (Archive,
                  // Delete) grouped below it. Ownership (which group this
                  // belongs to) is fixed at creation -- no reassignment here.
                  PopupMenuButton<String>(
                    icon: Icon(Icons.more_vert, color: Colors.grey.shade400),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    onSelected: (v) {
                      if (v == 'edit') _edit(context, data);
                      if (v == 'assign') _openAssignSheet(context, assignedTo);
                      if (v == 'delete') _delete(context, title);
                      if (v == 'archive')
                        _setStatus(
                          context,
                          title,
                          'archived',
                          'teacher.teacher_content_editor_screen.archiveContentTitle'.tr(),
                          'teacher.teacher_content_editor_screen.archiveContentMsg'
                              .tr(namedArgs: {'title': title}),
                          'teacher.group_card.archive'.tr(),
                        );
                      if (v == 'unarchive')
                        _setStatus(
                          context,
                          title,
                          'active',
                          'teacher.teacher_content_editor_screen.unarchiveContentTitle'.tr(),
                          'teacher.teacher_content_editor_screen.unarchiveContentMsg'
                              .tr(namedArgs: {'title': title}),
                          'teacher.group_card.unarchive'.tr(),
                        );
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'assign',
                        child: Row(
                          children: [
                            const Icon(Icons.group_add, size: 16, color: Colors.teal),
                            const SizedBox(width: 8),
                            Text('teacher.teacher_content_editor_screen.assignToGroups'.tr()),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'edit',
                        child: Row(
                          children: [
                            const Icon(
                              Icons.edit_outlined,
                              size: 16,
                              color: Colors.blue,
                            ),
                            const SizedBox(width: 8),
                            Text('common.edit'.tr()),
                          ],
                        ),
                      ),
                      // Manual archive/unarchive only applies to content
                      // with zero assigned groups -- once assigned, its
                      // availability is fully controlled by whether any
                      // assigned group is active (see
                      // Database.setGroupArchived/_syncContentArchivedFromGroups),
                      // so the manual action is hidden entirely rather than
                      // shown-but-ineffective.
                      if (assignedTo.isEmpty) ...[
                        const PopupMenuDivider(),
                        if (status == 'archived')
                          PopupMenuItem(
                            value: 'unarchive',
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.unarchive_outlined,
                                  size: 16,
                                  color: Colors.orange,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'teacher.group_card.unarchive'.tr(),
                                  style: const TextStyle(color: Colors.orange),
                                ),
                              ],
                            ),
                          )
                        else
                          PopupMenuItem(
                            value: 'archive',
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.archive_outlined,
                                  size: 16,
                                  color: Colors.orange,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'teacher.group_card.archive'.tr(),
                                  style: const TextStyle(color: Colors.orange),
                                ),
                              ],
                            ),
                          ),
                      ],
                      PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            const Icon(
                              Icons.delete_outline,
                              size: 16,
                              color: Colors.red,
                            ),
                            const SizedBox(width: 8),
                            Text('common.delete'.tr(), style: const TextStyle(color: Colors.red)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              // ── Description ──────────────────────────────────────────────
              if (desc.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  desc,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                    height: 1.4,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],

              // ── Footer (assigned groups, tap to open the Assign sheet) ────
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () => _openAssignSheet(context, assignedTo),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: assignedTo.isNotEmpty
                        ? _green.withOpacity(0.08)
                        : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: assignedTo.isNotEmpty
                          ? _green.withOpacity(0.3)
                          : Colors.grey.shade300,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.group,
                        size: 13,
                        color: assignedTo.isNotEmpty
                            ? _green
                            : Colors.grey.shade400,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        assignedTo.isEmpty
                            ? 'teacher.teacher_content_editor_screen.assignGroups'.tr()
                            : 'teacher.teacher_content_editor_screen.groupCount'
                                .plural(assignedTo.length),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: assignedTo.isNotEmpty
                              ? _green
                              : Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _edit(BuildContext context, Map<String, dynamic> data) => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => CreatePersonalizedContentScreen(
        contentId: doc.id,
        existingData: data,
        groupColor: _green,
      ),
    ),
  );

  // ── Assign flow entry point ────────────────────────────────────────────
  // Always opens the assign sheet, regardless of whether the content is
  // complete -- completeness only gates ADDING a new group assignment, it
  // must never hide or block access to groups the content is already
  // assigned to (a teacher must always be able to inspect/manage existing
  // assignments, even for partially-finished content).
  void _openAssignSheet(BuildContext context, List<String> current) =>
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _AssignSheet(contentId: doc.id, current: current),
      );

  Future<void> _delete(BuildContext context, String title) async {
    final ok = await showTeacherConfirmDialog(
      context: context,
      title: 'teacher.teacher_content_editor_screen.deleteContentTitle'.tr(),
      message: 'teacher.teacher_content_editor_screen.deleteContentMsg'
          .tr(namedArgs: {'title': title}),
      confirmLabel: 'common.delete'.tr(),
      cancelLabel: 'common.cancel'.tr(),
    );
    if (!ok) return;
    try {
      await Database().deletePersonalizedContent(doc.id);
      if (context.mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('teacher.teacher_content_editor_screen.contentDeleted'.tr()),
            backgroundColor: Colors.green,
          ),
        );
    } catch (e) {
      if (context.mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('common.errorWithMessage'.tr(namedArgs: {'error': '$e'})), backgroundColor: Colors.red),
        );
    }
  }

  Future<void> _setStatus(
    BuildContext context,
    String title,
    String newStatus,
    String dialogTitle,
    String message,
    String confirmLabel,
  ) async {
    final ok = await showTeacherConfirmDialog(
      context: context,
      title: dialogTitle,
      message: message,
      confirmLabel: confirmLabel,
      cancelLabel: 'common.cancel'.tr(),
    );
    if (!ok) return;
    try {
      await Database().setContentArchived(
        contentId: doc.id,
        archived: newStatus == 'archived',
      );
      if (context.mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('teacher.teacher_content_editor_screen.contentUpdated'.tr()),
            backgroundColor: Colors.green,
          ),
        );
    } catch (e) {
      if (context.mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('common.errorWithMessage'.tr(namedArgs: {'error': '$e'})), backgroundColor: Colors.red),
        );
    }
  }
}

// ── Assign group sheet ────────────────────────────────────────────────────
//
// Shows the content's current assignments and lets the teacher freely add
// or remove groups, gated by two safeguards:
//
// 1. A group checkbox is disabled (locked) if ContentAssignmentGuard finds
//    existing student progress for that content+group pair -- hard block,
//    no override path (see content_assignment_guard.dart for the
//    rationale). Scoped per (contentId, groupId), so a content already in
//    progress with one group stays freely assignable to/from a parallel
//    group with no progress of its own.
// 2. Saving doesn't write immediately -- it first confirms the change
//    ("Would you like to assign to <group>?" / "these groups?", plus any
//    unassignments), and only commits to Firestore once the teacher taps
//    Confirm. Nothing changed -> no dialog, just closes.
class _AssignSheet extends StatefulWidget {
  const _AssignSheet({required this.contentId, required this.current});
  final String contentId;
  final List<String> current;
  @override
  State<_AssignSheet> createState() => _AssignSheetState();
}

class _AssignSheetState extends State<_AssignSheet> {
  late Set<String> _sel;
  List<Map<String, dynamic>> _groups = [];
  Set<String> _lockedGroupIds = {};
  bool _loading = true, _saving = false;

  @override
  void initState() {
    super.initState();
    _sel = Set<String>.from(widget.current);
    _load();
  }

  Future<void> _load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final s = await FirebaseFirestore.instance
        .collection('teacherGroups')
        .where('teacherId', isEqualTo: uid)
        .get();
    final groups = s.docs.map((d) => {'id': d.id, ...d.data()}).toList();

    // Only groups currently assigned to this content can possibly have
    // student progress against it -- no point checking groups that were
    // never assigned.
    final assignedGroupIds = groups
        .map((g) => g['id'] as String)
        .where((id) => widget.current.contains(id))
        .toList();

    final locked = assignedGroupIds.isEmpty
        ? <String>{}
        : await ContentAssignmentGuard(Database()).lockedGroupIds(
            contentId: widget.contentId,
            groupIds: assignedGroupIds,
          );

    if (!mounted) return;
    setState(() {
      _groups = groups;
      _lockedGroupIds = locked;
      _loading = false;
    });
  }

  void _showCannotUnassignDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text(
            'teacher.teacher_content_editor_screen.cannotUnassignTitle'.tr()),
        content: Text(
            'teacher.teacher_content_editor_screen.cannotUnassignMsg'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('common.ok'.tr()),
          ),
        ],
      ),
    );
  }

  String _namesOf(Iterable<String> ids) => ids
      .map(
        (id) =>
            _groups.firstWhere(
                  (g) => g['id'] == id,
                  orElse: () => {
                    'name': 'teacher.teacher_content_editor_screen.group'.tr()
                  },
                )['name']
                as String,
      )
      .join(', ');

  Future<void> _save() async {
    final added = _sel.difference(Set<String>.from(widget.current));
    final removed = Set<String>.from(widget.current).difference(_sel);

    if (added.isEmpty && removed.isEmpty) {
      Navigator.pop(context);
      return;
    }

    final messageParts = <String>[];
    if (added.isNotEmpty) {
      messageParts.add(
        added.length == 1
            ? 'teacher.teacher_content_editor_screen.assignToOne'
                .tr(namedArgs: {'names': _namesOf(added)})
            : 'teacher.teacher_content_editor_screen.assignToMany'
                .tr(namedArgs: {'names': _namesOf(added)}),
      );
    }
    if (removed.isNotEmpty) {
      messageParts.add(
        removed.length == 1
            ? 'teacher.teacher_content_editor_screen.unassignFromOne'
                .tr(namedArgs: {'names': _namesOf(removed)})
            : 'teacher.teacher_content_editor_screen.unassignFromMany'
                .tr(namedArgs: {'names': _namesOf(removed)}),
      );
    }

    // A pure assign or pure unassign gets its own clear title; a save that
    // mixes both (some groups added, others removed at once) falls back to
    // the generic title since neither single-purpose title would fit.
    final String title;
    if (removed.isEmpty) {
      title = added.length == 1
          ? 'teacher.teacher_content_editor_screen.assignGroupTitle'.tr()
          : 'teacher.teacher_content_editor_screen.assignGroupsTitle'.tr();
    } else if (added.isEmpty) {
      title = 'teacher.teacher_content_editor_screen.unassignGroupTitle'.tr();
    } else {
      title = 'teacher.teacher_content_editor_screen.confirmAssignment'.tr();
    }

    final confirmed = await showTeacherConfirmDialog(
      context: context,
      title: title,
      message: messageParts.join('\n\n'),
      confirmLabel: 'common.confirm'.tr(),
      cancelLabel: 'common.cancel'.tr(),
      destructive: removed.isNotEmpty,
    );
    if (!confirmed || !mounted) return;

    setState(() => _saving = true);
    final db = Database();
    try {
      for (final g in added)
        await db.shareContentWithGroup(contentId: widget.contentId, groupId: g);
      for (final g in removed)
        await db.unshareContentFromGroup(
          contentId: widget.contentId,
          groupId: g,
        );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('common.errorWithMessage'.tr(namedArgs: {'error': '$e'})), backgroundColor: Colors.red),
        );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'teacher.teacher_content_editor_screen.assignToGroups'.tr(),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            'teacher.teacher_content_editor_screen.selectGroupsAccess'.tr(),
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 16),
          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_groups.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  'teacher.teacher_content_editor_screen.noGroupsFound'.tr(),
                  style: TextStyle(color: Colors.grey.shade500),
                ),
              ),
            )
          else
            // An archived group can never be a NEW assignment target --
            // only shown here at all if it's already in widget.current, so
            // an existing assignment to a group that later got archived
            // stays visible/manageable (still unassignable, subject to the
            // same progress lock as any other group).
            ..._groups
                .where((g) =>
                    g['archived'] != true ||
                    widget.current.contains(g['id'] as String))
                .map((g) {
              final id = g['id'] as String;
              final name = g['name'] as String? ??
                  'teacher.teacher_content_editor_screen.group'.tr();
              final isLocked = _lockedGroupIds.contains(id);

              final tile = Opacity(
                opacity: isLocked ? 0.6 : 1.0,
                child: CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Row(
                    children: [
                      Flexible(
                        child: Text(
                          name,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (isLocked) ...[
                        const SizedBox(width: 6),
                        Icon(
                          Icons.lock_outline,
                          size: 14,
                          color: Colors.grey.shade600,
                        ),
                      ],
                    ],
                  ),
                  subtitle: Text(
                    isLocked
                        ? 'teacher.teacher_content_editor_screen.alreadyHaveProgress'.tr()
                        : (g['groupCode'] as String? ?? ''),
                    style: TextStyle(
                      fontSize: 12,
                      color: isLocked ? Colors.orange.shade800 : Colors.grey,
                      fontWeight: isLocked
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                  ),
                  activeColor: AppColors.primary,
                  value: _sel.contains(id),
                  // Locked groups can never be unchecked -- onChanged blocks
                  // any attempt to remove a locked group from the selection.
                  onChanged: isLocked
                      ? null
                      : (v) =>
                            setState(() => v! ? _sel.add(id) : _sel.remove(id)),
                ),
              );

              // Locked tile has onChanged: null, so it never consumes a tap
              // itself -- wrapping it lets a tap still surface *why* it's
              // locked instead of just silently doing nothing.
              if (!isLocked) return tile;
              return GestureDetector(
                onTap: () => _showCannotUnassignDialog(context),
                child: tile,
              );
            }),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      'common.save'.tr(),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.folder_open_rounded,
            size: 80,
            color: Colors.grey.shade300,
          ),
          const SizedBox(height: 20),
          Text(
            'teacher.teacher_content_editor_screen.noContentYet'.tr(),
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          Text(
            'teacher.teacher_content_editor_screen.createFirstContentSubtitle'.tr(),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade500,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 28),
          ElevatedButton.icon(
            onPressed: onTap,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(Icons.add),
            label: Text(
              'teacher.teacher_content_editor_screen.createFirstContent'.tr(),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    ),
  );
}

// ── Filtered empty state (Active/Archived chip has nothing to show) ──────────
// Distinct from _EmptyState above: this fires when the teacher HAS content
// but none of it matches the current filter (e.g. no archived content yet),
// not when they have no content at all -- so it doesn't repeat the
// "Create First Content" CTA, which would be misleading here.

class _FilteredEmptyState extends StatelessWidget {
  const _FilteredEmptyState({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final icon = switch (status) {
      'archived' => Icons.archive_outlined,
      _ => Icons.folder_open_rounded,
    };
    final title = switch (status) {
      'archived' => 'teacher.teacher_content_editor_screen.noArchivedContent'.tr(),
      _ => 'teacher.teacher_content_editor_screen.noActiveContent'.tr(),
    };
    final subtitle = switch (status) {
      'archived' => 'teacher.teacher_content_editor_screen.archivedContentSubtitle'.tr(),
      _ => 'teacher.teacher_content_editor_screen.activeContentSubtitle'.tr(),
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade500,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
