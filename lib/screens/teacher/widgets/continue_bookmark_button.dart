// lib/screens/teacher/widgets/continue_bookmark_button.dart
//
// Bookmark button, shown on the CREATE forms (create_unit_screen.dart and
// siblings) -- not the list/view screens. Deliberately NOT called "Draft"
// anywhere in this UI -- that word is already taken by the separate
// content-level draft/active/archived status (see database.dart's
// setContentStatus), which controls whether a CONTENT ITEM can be
// assigned to groups. This is a different, unrelated mechanism: Units/
// Lessons/Activities/Tasks have no status of their own at all -- this is
// just a single pointer remembering where the teacher was mid-typing, so
// reusing "Draft" for it would (and did) conflate the two.
//
// Tapping it records exactly where the teacher is in the Content -> Unit
// -> Lesson -> Activity -> Task chain, PLUS whatever they'd typed into the
// form so far (via [getFormData]), through Database.saveContinueBookmark
// -- picked back up later by the "Continue where you left off" card on
// teacher_content_editor_screen.dart, which reopens the same create form
// pre-filled instead of landing on the parent list with the typed text
// lost.
//
// getFormData is a CALLBACK, not a plain Map -- the button widget is built
// once per parent rebuild, but a teacher keeps typing after that build, so
// reading controller .text values at build time would go stale. The
// callback defers that read to the moment the bookmark is actually saved,
// guaranteeing it reflects whatever's on screen right then.

import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:loringo_app/providers/locale_provider.dart';
import 'package:loringo_app/services/database/database.dart';
import 'package:loringo_app/theme/app_theme.dart';

class ContinueBookmarkButton extends StatelessWidget {
  const ContinueBookmarkButton({
    super.key,
    required this.level,
    required this.contentId,
    required this.getFormData,
    this.unitId,
    this.lessonId,
    this.activityId,
  });

  final String level; // 'unit' | 'lesson' | 'activity' | 'task'
  final String contentId;
  final Map<String, dynamic> Function() getFormData;
  final String? unitId;
  final String? lessonId;
  final String? activityId;

  Future<void> _save(BuildContext context) async {
    final teacherId = FirebaseAuth.instance.currentUser?.uid;
    if (teacherId == null) return;
    try {
      final db = Database();
      final titles = await db.resolveHierarchyTitles(
        contentId: contentId, unitId: unitId, lessonId: lessonId, activityId: activityId,
      );
      await db.saveContinueBookmark(
        teacherId: teacherId,
        level: level,
        contentId: contentId,
        contentTitle: titles['contentTitle'] ?? 'Content',
        unitId: unitId,
        unitTitle: titles['unitTitle'],
        lessonId: lessonId,
        lessonTitle: titles['lessonTitle'],
        activityId: activityId,
        activityTitle: titles['activityTitle'],
        formData: getFormData(),
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('teacher.continue_bookmark_button.savedSnackbar'.tr())),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text('common.errorWithMessage'.tr(namedArgs: {'error': '$e'})),
              backgroundColor: AppColors.danger),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LocaleProvider>();
    return IconButton(
      icon: const Icon(Icons.bookmark_add_outlined),
      tooltip: 'teacher.continue_bookmark_button.bookmarkTooltip'.tr(),
      onPressed: () => _save(context),
    );
  }
}
