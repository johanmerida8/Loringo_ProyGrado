import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:loringo_app/screens/teacher/content_details_screen.dart';
import 'package:loringo_app/screens/teacher/create_content_screen.dart';
import 'package:loringo_app/screens/teacher/widgets/teacher_confirm_dialog.dart';
import 'package:loringo_app/services/database/database.dart';
import 'package:loringo_app/theme/app_theme.dart';

// ── TeacherContentScreen ──────────────────────────────────────────────────────
// Lista de todos los contenidos del docente, agrupados por estado:
//   Approved  → card verde  → tap abre el árbol de unidades
//   Pending   → card naranja → solo editable
//   Rejected  → card rojo   → editable con razón de rechazo visible

class TeacherContentScreen extends StatelessWidget {
  const TeacherContentScreen({super.key});

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
      backgroundColor: const Color(0xFFF5F5F7),
      appBar: AppBar(
        backgroundColor: _green,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('My Content',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: _green,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('New Content', style: TextStyle(fontWeight: FontWeight.bold)),
        onPressed: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const CreatePersonalizedContentScreen())),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: Database().getTeacherContentStream(teacherId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: _green));
          }
          final docs = snapshot.data?.docs ?? [];

          if (docs.isEmpty) return _EmptyState(onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const CreatePersonalizedContentScreen())));

          final approved = docs.where((d) => d['status'] == 'approved').toList();
          final pending  = docs.where((d) => d['status'] == 'pending').toList();
          final rejected = docs.where((d) => d['status'] == 'rejected').toList();

          return CustomScrollView(
            slivers: [
              // ── Stats header ───────────────────────────────────────────
              SliverToBoxAdapter(
                child: Container(
                  color: _green,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                  child: Row(children: [
                    _statBadge('${approved.length}', 'Approved', Colors.white, _green),
                    const SizedBox(width: 10),
                    _statBadge('${pending.length}', 'Pending', Colors.orange.shade200, Colors.orange.shade800),
                    const SizedBox(width: 10),
                    _statBadge('${rejected.length}', 'Rejected', Colors.red.shade200, Colors.red.shade800),
                  ]),
                ),
              ),
              SliverToBoxAdapter(
                child: Container(
                  height: 20,
                  decoration: const BoxDecoration(
                    color: Color(0xFFF5F5F7),
                    borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(20), topRight: Radius.circular(20)),
                  ),
                ),
              ),

              // ── Sections ──────────────────────────────────────────────
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    if (approved.isNotEmpty) ...[
                      _SectionHeader(label: 'Approved', count: approved.length, color: Colors.green),
                      ...approved.map((d) => _ContentCard(doc: d, teacherId: teacherId)),
                      const SizedBox(height: 8),
                    ],
                    if (pending.isNotEmpty) ...[
                      _SectionHeader(label: 'Pending Review', count: pending.length, color: Colors.orange),
                      ...pending.map((d) => _ContentCard(doc: d, teacherId: teacherId)),
                      const SizedBox(height: 8),
                    ],
                    if (rejected.isNotEmpty) ...[
                      _SectionHeader(label: 'Rejected', count: rejected.length, color: Colors.red),
                      ...rejected.map((d) => _ContentCard(doc: d, teacherId: teacherId)),
                    ],
                  ]),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  static Widget _statBadge(String value, String label, Color bg, Color fg) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(color: bg.withOpacity(0.25), borderRadius: BorderRadius.circular(20)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Text(value, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
      const SizedBox(width: 5),
      Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
    ]),
  );
}

// ── Content card ──────────────────────────────────────────────────────────────

class _ContentCard extends StatelessWidget {
  const _ContentCard({required this.doc, required this.teacherId});
  final QueryDocumentSnapshot doc;
  final String teacherId;

  static const Color _green = AppColors.primary;

  @override
  Widget build(BuildContext context) {
    final data       = doc.data() as Map<String, dynamic>;
    final title      = data['title']    as String? ?? 'Untitled';
    final ageGroup   = data['ageGroup'] as String? ?? '';
    final desc       = data['description'] as String? ?? '';
    final status     = data['status']   as String? ?? 'pending';
    final assignedTo = (data['assignedTo'] as List?)?.cast<String>() ?? [];
    final initial    = title.isNotEmpty ? title[0].toUpperCase() : '#';

    final isApproved = status == 'approved';
    final isPending  = status == 'pending';
    final isRejected = status == 'rejected';

    // Status accent colour (left border)
    final Color accent = isApproved ? _green : isPending ? Colors.orange : Colors.red;

    return GestureDetector(
      onTap: isApproved
          ? () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => PersonalizedContentDetailsScreen(
                  groupId: '', contentId: doc.id,
                  contentTitle: title, groupColor: _green)))
          : isRejected
              ? () => _edit(context, data)
              : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border(left: BorderSide(color: accent, width: 4)),
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
                  color: accent.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Center(child: Text(initial,
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: accent))),
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
                  if (v == 'assign') _assign(context, assignedTo);
                },
                itemBuilder: (_) => [
                  if (isApproved)
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

            // ── Footer (group chip only) ─────────────────────────────────
            if (isApproved) ...[
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () => _assign(context, assignedTo),
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
            ],

            // ── Rejected reason preview ───────────────────────────────────
            if (isRejected) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade100),
                ),
                child: Row(children: [
                  Icon(Icons.info_outline, size: 14, color: Colors.red.shade400),
                  const SizedBox(width: 6),
                  Expanded(child: Text('Tap to edit and resubmit',
                      style: TextStyle(fontSize: 11, color: Colors.red.shade600))),
                ]),
              ),
            ],

            // ── Pending info ──────────────────────────────────────────────
            if (isPending) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade100),
                ),
                child: Row(children: [
                  Icon(Icons.hourglass_top_rounded, size: 13, color: Colors.orange.shade600),
                  const SizedBox(width: 6),
                  Text('Awaiting admin approval',
                      style: TextStyle(fontSize: 11, color: Colors.orange.shade700, fontWeight: FontWeight.w500)),
                ]),
              ),
            ],
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

  void _assign(BuildContext context, List<String> current) =>
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _AssignSheet(contentId: doc.id, current: current),
      );
}

// ── Status badge ──────────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color fg;
    final IconData icon;
    final String label;

    switch (status) {
      case 'approved':
        bg = Colors.green.shade50; fg = Colors.green.shade700;
        icon = Icons.check_circle_rounded; label = 'Approved'; break;
      case 'pending':
        bg = Colors.orange.shade50; fg = Colors.orange.shade700;
        icon = Icons.hourglass_top_rounded; label = 'Pending'; break;
      default:
        bg = Colors.red.shade50; fg = Colors.red.shade700;
        icon = Icons.cancel_rounded; label = 'Rejected';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: fg),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 11, color: fg, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

// ── Section header ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, required this.count, required this.color});
  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10, top: 4),
    child: Row(children: [
      Container(width: 3, height: 16, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
      const SizedBox(width: 8),
      Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.grey.shade700)),
      const SizedBox(width: 6),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
        child: Text('$count', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color)),
      ),
    ]),
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
        Text('Create your first content unit. Once approved\nby an admin, you can assign it to your groups.',
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

class _AssignSheet extends StatefulWidget {
  const _AssignSheet({required this.contentId, required this.current});
  final String contentId;
  final List<String> current;
  @override State<_AssignSheet> createState() => _AssignSheetState();
}

class _AssignSheetState extends State<_AssignSheet> {
  late Set<String> _sel;
  List<Map<String, dynamic>> _groups = [];
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
    setState(() {
      _groups = s.docs.map((d) => {'id': d.id, ...d.data()}).toList();
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
          return CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(g['groupCode'] as String? ?? '',
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
            activeColor: AppColors.primary,
            value: _sel.contains(id),
            onChanged: (v) => setState(() => v! ? _sel.add(id) : _sel.remove(id)),
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