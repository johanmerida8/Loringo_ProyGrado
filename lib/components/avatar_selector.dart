import 'package:flutter/material.dart';
import 'package:loringo_app/theme/app_theme.dart';

/// Avatar Selector Widget
/// Allows users to select an avatar from predefined options
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

  // Lista de avatares disponibles
  final List<String> avatars = [
    'assets/avatars/arctic-fox.png',
    'assets/avatars/bear.png',
    'assets/avatars/beaver.png',
    'assets/avatars/cat.png',
    'assets/avatars/deer.png',
    'assets/avatars/dinosaur.png',
    'assets/avatars/dog.png',
    'assets/avatars/elephant.png',
    'assets/avatars/frog.png',
    'assets/avatars/giraffe.png',
    'assets/avatars/gorilla.png',
    'assets/avatars/koala.png',
    'assets/avatars/lizard.png',
    'assets/avatars/monkey.png',
    'assets/avatars/otter.png',
    'assets/avatars/panda.png',
    'assets/avatars/parrot.png',
    'assets/avatars/penguin.png',
    'assets/avatars/raccoon.png',
    'assets/avatars/squirrel.png',
    'assets/avatars/turtle.png',
    'assets/avatars/zebra.png',
  ];

  @override
  void initState() {
    super.initState();
    selectedAvatar = widget.currentAvatar;
  }

  @override
  Widget build(BuildContext context) {
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
                const Expanded(
                  child: Text(
                    'Choose your Avatar',
                    style: TextStyle(
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
              constraints: const BoxConstraints(maxHeight: 400),
              child: GridView.builder(
                shrinkWrap: true,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1,
                ),
                itemCount: avatars.length,
                itemBuilder: (context, index) {
                  final avatar = avatars[index];
                  final isSelected = selectedAvatar == avatar;

                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        selectedAvatar = avatar;
                      });
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.tint(AppColors.primary, .15)
                            : AppColors.subtleFill,
                        borderRadius: AppRadii.lgAll,
                        border: Border.all(
                          color: isSelected
                              ? AppColors.primary
                              : AppColors.divider,
                          width: isSelected ? 3 : 1,
                        ),
                        boxShadow: isSelected
                            ? AppShadows.floating(AppColors.primary)
                            : [],
                      ),
                      child: Stack(
                        children: [
                          Center(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Image.asset(
                                avatar,
                                fit: BoxFit.contain,
                                errorBuilder: (context, error, stackTrace) {
                                  return Icon(
                                    Icons.image_not_supported,
                                    color: AppColors.muted,
                                    size: 40,
                                  );
                                },
                              ),
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
              ),
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
                child: const Text(
                  'Confirm Avatar',
                  style: AppText.button,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}