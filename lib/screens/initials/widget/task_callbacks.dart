// widget/task_callbacks.dart
//
// ── TEACHER REVIEW FEATURE — shared callback typedefs ───────────────────
//
// Every one of the 13 task screens (ScreenOne..ScreenTwelve, plus
// ScreenSeven's multi-part variant) calls back into ActivityPlayScreen
// when the student finishes a task. Before this feature, that callback
// only carried a bool (isCorrect). To let teachers review exactly what a
// student answered on each task, every screen now also reports an
// "answerDetail" map — a type-specific description of the student's
// answer vs. the correct one.
//
// WHY A SHARED TYPEDEF INSTEAD OF INLINE FUNCTION TYPES PER FILE:
// Dart's structural typing means an inline `Function(bool, [Map])` in
// one file is only assignable to another file's inline
// `Function(bool, [Map])?` if the two signatures are structurally
// identical (parameter kinds, optionality, order). Repeating the literal
// signature across 14 files (13 task screens + the parent) is an easy
// place to introduce a subtle mismatch — e.g. one file using a named
// optional parameter, another a positional one — that would only surface
// as a confusing type error deep in ActivityPlayScreen's widget tree.
// Importing ONE typedef everywhere guarantees every file means exactly
// the same type, and if the shape ever needs to change, there is exactly
// one declaration to update.
//
// `answerDetail` deliberately stays `Map<String, dynamic>` (no shared
// schema beyond a 'type' key) because each of the ~10 task types records
// a fundamentally different shape of "what did the student answer" —
// see each screen_*.dart's _checkAnswer for its own shape, and
// ActivityReviewScreen for the per-type rendering switch.

/// Used by every single-answer task screen (image_select, arrange,
/// fill_blank, match, sentence_builder, repeat_after_me,
/// listen_and_speak, sound_match, odd_one_out, complete_the_chat).
/// [answerDetail] defaults to an empty map so existing call sites that
/// haven't been migrated to pass it yet don't break.
typedef TaskCompleteCallback = void Function(
  bool isCorrect, [
  Map<String, dynamic> answerDetail,
]);

/// Used only by the 'reading' task type (ScreenSeven), which contains
/// several independently-scored sub-questions inside a single task
/// document. [subQuestionDetails] carries one answerDetail-shaped map
/// per sub-question rather than a single flat map.
typedef MultiPartTaskCompleteCallback = void Function(
  bool pass,
  int subCorrect,
  int subWrong, [
  List<Map<String, dynamic>> subQuestionDetails,
]);