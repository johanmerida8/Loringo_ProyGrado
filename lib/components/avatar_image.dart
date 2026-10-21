import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

// ── AvatarImage ──────────────────────────────────────────────────────────────
//
// Renders an `avatar` string that may be either a legacy bundled asset path
// (e.g. "assets/avatars/parrot.png", from before avatars moved to Cloudinary)
// or a Cloudinary secure_url (the new format, returned by
// AvatarSelector/ImageService.fetchAvatarOptions). Self-heals both shapes at
// render time — no Firestore migration needed, old and new values coexist.
//
// A network load failure (offline, broken URL) falls back to a single
// generic local asset rather than trying to match the specific avatar —
// Cloudinary's random-suffixed public IDs can't be reliably mapped back to
// one specific local file by name.
const String kAvatarFallbackAsset = 'assets/avatars/panda.png';

class AvatarImage extends StatelessWidget {
  final String? avatar;
  final double? size;
  final BoxFit fit;

  /// Overrides the default generic-asset fallback (e.g. to show the
  /// child/user's initial letter instead) when [avatar] is missing or fails
  /// to load.
  final WidgetBuilder? fallbackBuilder;

  const AvatarImage({
    super.key,
    required this.avatar,
    this.size,
    this.fit = BoxFit.contain,
    this.fallbackBuilder,
  });

  Widget _fallback(BuildContext context) {
    if (fallbackBuilder != null) return fallbackBuilder!(context);
    return Image.asset(kAvatarFallbackAsset, width: size, height: size, fit: fit);
  }

  @override
  Widget build(BuildContext context) {
    final value = avatar;
    if (value == null || value.isEmpty) {
      return _fallback(context);
    }
    if (value.startsWith('http')) {
      return CachedNetworkImage(
        imageUrl: value,
        width: size,
        height: size,
        fit: fit,
        placeholder: (context, url) => SizedBox(
          width: size,
          height: size,
          child: const Center(
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
        errorWidget: (context, url, error) => _fallback(context),
      );
    }
    return Image.asset(
      value,
      width: size,
      height: size,
      fit: fit,
      errorBuilder: (context, error, stackTrace) => _fallback(context),
    );
  }
}

/// For `CircleAvatar(backgroundImage: ...)` call sites, which need an
/// [ImageProvider] rather than a widget. `CircleAvatar` has no built-in
/// fallback-asset swap on error (only `onBackgroundImageError`) — call sites
/// using this should pass `onBackgroundImageError: (_, __) {}` and keep
/// their existing initials/icon fallback as the visual safety net.
ImageProvider avatarImageProvider(String avatar) {
  if (avatar.startsWith('http')) return CachedNetworkImageProvider(avatar);
  return AssetImage(avatar);
}
