import 'package:file_picker/file_picker.dart';

/// A staged change on an image-library item, applied later in batch from
/// the Confirm button of AdminViewImagesScreen / TeacherViewImagesScreen.
enum ImagePendingKind { delete, replace }

class ImagePendingOp {
  final ImagePendingKind kind;

  /// The replacement file; only set when [kind] is replace.
  final PlatformFile? file;

  ImagePendingOp.delete() : kind = ImagePendingKind.delete, file = null;
  ImagePendingOp.replace(PlatformFile this.file)
      : kind = ImagePendingKind.replace;
}
