// Re-export the app-wide theme so teacher widgets can import either file.
export 'package:loringo_app/theme/app_theme.dart';

import 'package:loringo_app/theme/app_theme.dart';

// Backward-compatibility aliases — existing code using TeacherColors etc.
// continues to work without any changes.
typedef TeacherColors = AppColors;
typedef TeacherSpacing = AppSpacing;
typedef TeacherRadii = AppRadii;
typedef TeacherText = AppText;
typedef TeacherDecorations = AppDecorations;
