// admin_dashboard_screen.dart
import 'package:flutter/material.dart';
import 'package:loringo_app/services/database/database.dart';
import 'package:loringo_app/theme/app_theme.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen>
    with SingleTickerProviderStateMixin {
  final Database _db = Database();
  late AnimationController _animCtrl;
  late Animation<double> _fadeIn;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _fadeIn = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeIn,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.md, AppSpacing.md, AppSpacing.md, 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Hero welcome card ─────────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                gradient: AppDecorations.primaryGradient,
                borderRadius: BorderRadius.circular(AppRadii.lg),
                boxShadow: [
                  BoxShadow(
                      color: AppColors.primarySoft(0.35),
                      blurRadius: 20,
                      offset: const Offset(0, 8)),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.sm + 2),
                      decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(AppRadii.md)),
                      child: const Icon(Icons.admin_panel_settings_rounded,
                          color: AppColors.onPrimary, size: 26),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Admin Dashboard',
                              style: TextStyle(
                                  color: AppColors.onPrimary,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold)),
                          Text('System Oversight',
                              style: TextStyle(
                                  color: Colors.white70, fontSize: 13)),
                        ]),
                  ]),
                  const SizedBox(height: AppSpacing.md),
                  const Text(
                    'Manage and oversee all platform content, approvals and media assets.',
                    style: TextStyle(
                        color: Colors.white70, fontSize: 13, height: 1.5),
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.lg),

            // ── Section label ─────────────────────────────────────────────
            Row(children: [
              Container(
                width: 4, height: 18,
                decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(width: AppSpacing.sm),
              const Text('System Statistics',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            ]),

            const SizedBox(height: AppSpacing.md),

            // ── Stats grid ────────────────────────────────────────────────
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: AppSpacing.md,
              mainAxisSpacing: AppSpacing.md,
              childAspectRatio: 1.05,
              children: [
                FutureBuilder<int>(
                  future: _db.getTotalImagesCount(),
                  builder: (_, snap) => _StatCard(
                    label: 'Total Images',
                    value: snap.data?.toString() ?? '—',
                    icon: Icons.image_rounded,
                    color: const Color(0xFF2196F3),
                    isLoading:
                        snap.connectionState == ConnectionState.waiting,
                  ),
                ),
                StreamBuilder<int>(
                  stream: _db.getCategoriesCountStream(),
                  builder: (_, snap) => _StatCard(
                    label: 'Categories',
                    value: snap.data?.toString() ?? '—',
                    icon: Icons.folder_rounded,
                    color: Colors.orange,
                    isLoading:
                        snap.connectionState == ConnectionState.waiting,
                  ),
                ),
                StreamBuilder<int>(
                  stream: _db.getApprovedContentCountStream(),
                  builder: (_, snap) => _StatCard(
                    label: 'Approved Content',
                    value: snap.data?.toString() ?? '—',
                    icon: Icons.check_circle_rounded,
                    color: AppColors.primary,
                    isLoading:
                        snap.connectionState == ConnectionState.waiting,
                  ),
                ),
                StreamBuilder<int>(
                  stream: _db.getPendingContentCountStream(),
                  builder: (_, snap) => _StatCard(
                    label: 'Pending Approval',
                    value: snap.data?.toString() ?? '—',
                    icon: Icons.hourglass_bottom_rounded,
                    color: Colors.amber[700]!,
                    isLoading:
                        snap.connectionState == ConnectionState.waiting,
                  ),
                ),
              ],
            ),

            const SizedBox(height: AppSpacing.lg),

            // ── Info banner ───────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md, vertical: AppSpacing.md - 2),
              decoration: BoxDecoration(
                color: const Color(0xFF2196F3).withOpacity(0.07),
                borderRadius: BorderRadius.circular(AppRadii.md),
                border: Border.all(
                    color: const Color(0xFF2196F3).withOpacity(0.2)),
              ),
              child: const Row(children: [
                Icon(Icons.sync_rounded,
                    color: Color(0xFF2196F3), size: 20),
                SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text('Dashboard updates in real-time',
                      style: TextStyle(
                          color: Color(0xFF2196F3),
                          fontSize: 13,
                          fontWeight: FontWeight.w500)),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Stat card ─────────────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final bool isLoading;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 12,
              offset: const Offset(0, 4)),
        ],
        border: Border.all(color: color.withOpacity(0.15), width: 1.5),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.md - 2),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 28, color: color),
          ),
          const SizedBox(height: AppSpacing.sm),
          isLoading
              ? SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: color))
              : Text(value,
                  style: const TextStyle(
                      fontSize: 28, fontWeight: FontWeight.bold,
                      letterSpacing: -0.5)),
          const SizedBox(height: AppSpacing.xs + 2),
          Text(label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}