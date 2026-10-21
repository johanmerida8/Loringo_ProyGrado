import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:loringo_app/components/avatar_image.dart';
import 'package:loringo_app/providers/locale_provider.dart';
import 'package:loringo_app/theme/app_theme.dart';
import 'package:loringo_app/utils/image_service.dart';

/// Avatar Selector Widget
/// Lets the user pick an avatar from Cloudinary's "avatars" folder, fetched
/// dynamically (see ImageService.fetchAvatarOptions) — no hardcoded list.
/// Returns the chosen avatar's Cloudinary secure_url on confirm.
class AvatarSelector extends StatefulWidget {
  final String? currentAvatar;
  final Function(String) onAvatarSelected;

  const AvatarSelector({
    super.key,
    this.currentAvatar,
    required this.onAvatarSelected,
  });

  @override
  State<AvatarSelector> createState() => _AvatarSelectorState();
}

class _AvatarSelectorState extends State<AvatarSelector> {
  String? selectedAvatar;
  List<Map<String, String>>? _avatars;
  bool _loading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    selectedAvatar = widget.currentAvatar;
    _loadAvatars();
  }

  Future<void> _loadAvatars({bool forceRefresh = false}) async {
    setState(() {
      _loading = true;
      _hasError = false;
    });
    try {
      final avatars = await ImageService().fetchAvatarOptions(forceRefresh: forceRefresh);
      if (mounted) setState(() => _avatars = avatars);
    } catch (e) {
      // ignore: avoid_print
      print('[AVATAR SELECTOR] fetchAvatarOptions failed: $e');
      if (mounted) setState(() => _hasError = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LocaleProvider>();
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: AppRadii.lgAll),
      child: Container(
        padding: const EdgeInsets.all(20),
        constraints: const BoxConstraints(maxWidth: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.tint(AppColors.primary),
                    borderRadius: AppRadii.mdAll,
                  ),
                  child: const Icon(
                    Icons.face_rounded,
                    color: AppColors.primary,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'components.avatar_selector.chooseAvatar'.tr(),
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primaryDark,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                  color: AppColors.muted,
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Avatar Grid
            Container(
              constraints: const BoxConstraints(maxHeight: 400, minHeight: 120),
              child: _buildGridContent(),
            ),

            const SizedBox(height: 20),

            // Confirm Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: selectedAvatar != null
                    ? () {
                        widget.onAvatarSelected(selectedAvatar!);
                        Navigator.pop(context);
                      }
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.onPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: AppRadii.mdAll,
                  ),
                  elevation: 3,
                  disabledBackgroundColor: Colors.grey[300],
                ),
                child: Text(
                  'components.avatar_selector.confirmAvatar'.tr(),
                  style: AppText.button,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGridContent() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_hasError || _avatars == null || _avatars!.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, color: AppColors.muted, size: 40),
            const SizedBox(height: 12),
            Text(
              'components.avatar_selector.loadFailed'.tr(),
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => _loadAvatars(forceRefresh: true),
              child: Text('common.retry'.tr()),
            ),
          ],
        ),
      );
    }

    final avatars = _avatars!;
    return GridView.builder(
      shrinkWrap: true,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1,
      ),
      itemCount: avatars.length,
      itemBuilder: (context, index) {
        final avatarUrl = avatars[index]['url']!;
        final isSelected = selectedAvatar == avatarUrl;

        return GestureDetector(
          onTap: () {
            setState(() {
              selectedAvatar = avatarUrl;
            });
          },
          child: Container(
            decoration: BoxDecoration(
              color: isSelected
                  ? AppColors.tint(AppColors.primary, .15)
                  : AppColors.subtleFill,
              borderRadius: AppRadii.lgAll,
              border: Border.all(
                color: isSelected ? AppColors.primary : AppColors.divider,
                width: isSelected ? 3 : 1,
              ),
              boxShadow: isSelected ? AppShadows.floating(AppColors.primary) : [],
            ),
            child: Stack(
              children: [
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: AvatarImage(avatar: avatarUrl),
                  ),
                ),
                if (isSelected)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: AppColors.success,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check,
                        color: AppColors.onPrimary,
                        size: 16,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
