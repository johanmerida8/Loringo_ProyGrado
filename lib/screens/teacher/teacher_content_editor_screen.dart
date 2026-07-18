import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:loringo_app/screens/teacher/teacher_unit_editor_screen.dart';
import 'package:loringo_app/screens/teacher/create_content_screen.dart';
import 'package:loringo_app/screens/teacher/widgets/teacher_confirm_dialog.dart';
import 'package:loringo_app/screens/teacher/widgets/teacher_screen_header.dart';
import 'package:loringo_app/services/database/database.dart';
import 'package:loringo_app/services/content/content_assignment_guard.dart';
import 'package:loringo_app/theme/app_theme.dart';

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
// ASSIGNMENT SAFETY: teachers can build content incrementally and assign
// it as soon as it has anything usable — there is no completeness gate.
// A teacher is expected to start with one Unit and one Lesson, publish it,
// and keep adding more over time, including after a group is already
// using it. The only thing this screen still guards is the assign sheet's
// per-group checkbox: ContentAssignmentGuard disables unchecking a group
// that already has recorded student progress for this content (hard
// block, no override path — see content_assignment_guard.dart). That
// guard is scoped per (contentId, groupId) pair, so a content already in
// progress with one group can still be freely assigned to or unassigned
// from a different, parallel group with no progress of its own.

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

class _Body extends StatelessWidget {
  const _Body({required this.teacherId});
  final String teacherId;

  static const Color _green = AppColors.primary;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBackground,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: _green,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('New Content', style: TextStyle(fontWeight: FontWeight.bold)),
        onPressed: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const CreatePersonalizedContentScreen())),
      ),
      body: Column(
        children: [
          const TeacherScreenHeader(
            title: 'My Content',
            color: _green,
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: Database().getTeacherContentStream(teacherId),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: _green));
                }
                final docs = snapshot.data?.docs ?? [];

                if (docs.isEmpty) {
                  return _EmptyState(onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const CreatePersonalizedContentScreen())));
                }

                return CustomScrollView(
                  slivers: [
                    // ── Stats badge ────────────────────────────────────
                    // Was previously a colored strip (Container(color:
                    // _green, ...)); now a plain inline chip sitting on
                    // the scaffold background, consistent with the
                    // no-AppBar/no-colored-bar rule.
                    // SliverToBoxAdapter(
                    //   child: Padding(
                    //     padding: const EdgeInsets.fromLTRB(
                    //         AppSpacing.md, 0, AppSpacing.md, AppSpacing.sm),
                    //     child: Row(children: [
                    //       _statBadge('${docs.length}', 'Total Content'),
                    //     ]),
                    //   ),
                    // ),

                    // ── Content list ──────────────────────────────────
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final doc = docs[index];
                            return _ContentCard(doc: doc, teacherId: teacherId);
                          },
                          childCount: docs.length,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // static Widget _statBadge(String value, String label) => Container(
  //   padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
  //   decoration: BoxDecoration(color: AppColors.primarySoft(0.1), borderRadius: BorderRadius.circular(20)),
  //   child: Row(mainAxisSize: MainAxisSize.min, children: [
  //     Text(value, style: const TextStyle(color: _green, fontWeight: FontWeight.bold, fontSize: 15)),
  //     const SizedBox(width: 5),
  //     Text(label, style: TextStyle(color: _green.withOpacity(0.75), fontSize: 11)),
  //   ]),
  // );
}

// ── Content card ──────────────────────────────────────────────────────────────

class _ContentCard extends StatelessWidget {
  const _ContentCard({required this.doc, required this.teacherId});
  final QueryDocumentSnapshot doc;
  final String teacherId;

  static const Color _green = AppColors.primary;

  @override
  Widget build(BuildContext context) {
    final data        = doc.data() as Map<String, dynamic>;
    final title       = data['title']    as String? ?? 'Untitled';
    final ageGroup    = data['ageGroup'] as String? ?? '';
    final desc        = data['description'] as String? ?? '';
    final assignedTo  = (data['assignedTo'] as List?)?.cast<String>() ?? [];
    final initial     = title.isNotEmpty ? title[0].toUpperCase() : '#';

    return GestureDetector(
      onTap: () => Navigator.push(context, 
        MaterialPageRoute(
          builder: (_) => TeacherUnitEditorScreen(
            groupId: '', 
            contentId: doc.id,
            contentTitle: title, 
            groupColor: _green
          )
        )
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border(left: BorderSide(color: _green, width: 4)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

            // ── Top row ──────────────────────────────────────────────────
            Row(children: [
              // Avatar
              Container(
                width: 42, height: 42,
                decoration: BoxDecoration(
                  color: _green.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Center(child: Text(initial,
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: _green))),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black87)),
                const SizedBox(height: 2),
                Row(children: [
                  Icon(Icons.cake_outlined, size: 12, color: Colors.grey.shade400),
                  const SizedBox(width: 3),
                  Text(ageGroup, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                ]),
              ])),
              // Actions menu
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert, color: Colors.grey.shade400),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                onSelected: (v) {
                  if (v == 'edit')   _edit(context, data);
                  if (v == 'delete') _delete(context, title);
                  if (v == 'assign') _onAssignTapped(context, assignedTo);
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'assign',
                      child: Row(children: [Icon(Icons.group_add, size: 16), SizedBox(width: 8), Text('Assign to Groups')])),
                  const PopupMenuItem(value: 'edit',
                      child: Row(children: [Icon(Icons.edit_outlined, size: 16, color: Colors.blue), SizedBox(width: 8), Text('Edit')])),
                  const PopupMenuItem(value: 'delete',
                      child: Row(children: [Icon(Icons.delete_outline, size: 16, color: Colors.red), SizedBox(width: 8), Text('Delete', style: TextStyle(color: Colors.red))])),
                ],
              ),
            ]),

            // ── Description ──────────────────────────────────────────────
            if (desc.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(desc,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600, height: 1.4),
                  maxLines: 2, overflow: TextOverflow.ellipsis),
            ],

            // ── Footer (group chip) ─────────────────────────────────────
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () => _onAssignTapped(context, assignedTo),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: assignedTo.isNotEmpty ? _green.withOpacity(0.08) : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: assignedTo.isNotEmpty ? _green.withOpacity(0.3) : Colors.grey.shade300),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.group, size: 13, color: assignedTo.isNotEmpty ? _green : Colors.grey.shade400),
                  const SizedBox(width: 4),
                  Text(
                    assignedTo.isEmpty ? 'Assign groups' : '${assignedTo.length} group${assignedTo.length != 1 ? 's' : ''}',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                        color: assignedTo.isNotEmpty ? _green : Colors.grey.shade500),
                  ),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  void _edit(BuildContext context, Map<String, dynamic> data) =>
      Navigator.push(context, MaterialPageRoute(
          builder: (_) => CreatePersonalizedContentScreen(
              contentId: doc.id, existingData: data, groupColor: _green)));

  Future<void> _delete(BuildContext context, String title) async {
    final ok = await showTeacherConfirmDialog(
      context: context, title: 'Delete Content',
      message: 'Delete "$title"? This cannot be undone.',
      confirmLabel: 'Delete', cancelLabel: 'Cancel',
    );
    if (!ok) return;
    try {
      await Database().deletePersonalizedContent(doc.id);
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Content deleted'), backgroundColor: Colors.green));
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    }
  }

  // ── Assign flow entry point ────────────────────────────────────────────
  // IMPORTANT: this always opens the assign sheet, regardless of whether
  // the content is complete. Completeness only gates ADDING a new group
  // assignment — it must never hide or block access to groups the content
  // is already assigned to. An earlier version of this screen ran the
  // completeness check here and refused to open the sheet at all when the
  // content was incomplete, which meant a teacher with partially-finished
  // content (e.g. Unit 2 still missing its Unit Test) couldn't even SEE
  // which groups it was already assigned to. That's a strictly worse bug
  // than an incomplete content being assignable — a teacher must always be
  // able to inspect and manage existing assignments.
  void _onAssignTapped(BuildContext context, List<String> current) {
    _openAssignSheet(context, current);
  }

  void _openAssignSheet(BuildContext context, List<String> current) =>
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _AssignSheet(contentId: doc.id, current: current),
      );
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(40),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.folder_open_rounded, size: 80, color: Colors.grey.shade300),
        const SizedBox(height: 20),
        const Text('No Content Yet',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        Text('Create your first content unit to get started.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade500, height: 1.5)),
        const SizedBox(height: 28),
        ElevatedButton.icon(
          onPressed: onTap,
          style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary, foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          icon: const Icon(Icons.add),
          label: const Text('Create First Content', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ]),
    ),
  );
}

// ── Assign group sheet ────────────────────────────────────────────────────────
//
// This sheet always shows the content's current assignments and lets the
// teacher freely add or remove groups. The only restriction is student
// progress: a group checkbox is disabled (locked) if ContentAssignmentGuard
// finds existing student progress for that content+group pair — hard
// block, no override path (see content_assignment_guard.dart for the
// rationale). This guard is scoped per (contentId, groupId), so the same
// content already in progress with one group (e.g. a section that started
// the unit) stays freely assignable to a parallel group with no progress
// of its own.

class _AssignSheet extends StatefulWidget {
  const _AssignSheet({required this.contentId, required this.current});
  final String contentId;
  final List<String> current;
  @override State<_AssignSheet> createState() => _AssignSheetState();
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
        .collection('teacherGroups').where('teacherId', isEqualTo: uid).get();
    final groups = s.docs.map((d) => {'id': d.id, ...d.data()}).toList();

    // Only groups currently assigned to this content can possibly have
    // student progress against it — no point checking groups that were
    // never assigned. Cast is safe: 'id' is always a String, set above.
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

  Future<void> _save() async {
    setState(() => _saving = true);
    final db = Database();
    final added   = _sel.difference(Set<String>.from(widget.current));
    final removed = Set<String>.from(widget.current).difference(_sel);
    try {
      for (final g in added)   await db.assignContentToGroup(contentId: widget.contentId, groupId: g);
      for (final g in removed) await db.removeContentFromGroup(contentId: widget.contentId, groupId: g);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(child: Container(width: 36, height: 4,
            decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
        const SizedBox(height: 16),
        const Text('Assign to Groups', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text('Select which groups can access this content',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
        const SizedBox(height: 16),
        if (_loading) const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
        else if (_groups.isEmpty)
          Padding(padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(child: Text('No groups found', style: TextStyle(color: Colors.grey.shade500))))
        else ..._groups.map((g) {
          final id = g['id'] as String;
          final name = g['name'] as String? ?? 'Group';
          final isLocked = _lockedGroupIds.contains(id);

          return Opacity(
            opacity: isLocked ? 0.6 : 1.0,
            child: CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: Row(children: [
                Flexible(child: Text(name, style: const TextStyle(fontWeight: FontWeight.w600))),
                if (isLocked) ...[
                  const SizedBox(width: 6),
                  Icon(Icons.lock_outline, size: 14, color: Colors.grey.shade600),
                ],
              ]),
              subtitle: Text(
                isLocked
                    ? 'Students already have progress — can\'t be unassigned'
                    : (g['groupCode'] as String? ?? ''),
                style: TextStyle(
                  fontSize: 12,
                  color: isLocked ? Colors.orange.shade800 : Colors.grey,
                  fontWeight: isLocked ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
              activeColor: AppColors.primary,
              value: _sel.contains(id),
              // Locked groups can never be unchecked. The onChanged
              // callback itself blocks any attempt to remove a locked
              // group from the selection — the tile stays visible either
              // way, it just stops responding to taps.
              onChanged: isLocked
                  ? null
                  : (v) => setState(() => v! ? _sel.add(id) : _sel.remove(id)),
            ),
          );
        }),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _saving ? null : _save,
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary, foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: _saving
                ? const SizedBox(height: 20, width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Save', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ),
      ]),
    );
  }
}