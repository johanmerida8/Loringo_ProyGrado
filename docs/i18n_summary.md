# i18n (English/Spanish) Implementation Summary

Reference doc for the language-switching feature built into Loringo.
Written to avoid re-deriving this context in future sessions.

## Package & Approach

- Package: **`easy_localization`** (`^3.0.7`) — JSON translation files +
  `.tr()` extension syntax. Deliberately chosen over Flutter's built-in
  ARB/`gen-l10n`.
- Translation files: `assets/translations/en.json` and
  `assets/translations/es.json` — the single source of truth for all
  user-facing strings covered so far.
- Supports system-language auto-detection on first launch, plus a manual
  in-app override that persists across sessions (via `easy_localization`'s
  built-in `saveLocale`, same persistence mechanism the app already used
  for biometric/notification toggles).

## Infrastructure

- `pubspec.yaml`: `easy_localization` dependency + `assets/translations/`
  registered under `flutter: assets:`.
- `lib/main.dart`: `EasyLocalization` widget wraps `runApp`;
  `ChangeNotifierProvider(create: (_) => LocaleProvider())` — **note:**
  `create` must never touch `BuildContext`/`context.locale` here (see Bugs
  Fixed below); `MaterialApp` wired with
  `context.localizationDelegates` / `supportedLocales` / `locale`.
- `lib/providers/locale_provider.dart` — `LocaleProvider extends
  ChangeNotifier`, mirrors the existing `BiometricProvider`/
  `NotificationProvider` pattern:
  ```dart
  class LocaleProvider extends ChangeNotifier {
    Future<void> setLocale(BuildContext context, Locale locale) async {
      if (context.locale == locale) return;
      await context.setLocale(locale);
      notifyListeners();
    }
  }
  ```
- `lib/components/language_selector.dart` — the selector widget. Reads
  `context.locale` directly for display, uses
  `context.read<LocaleProvider>()` to dispatch changes.
- **Selector placement** (explicit product decision): inside each role's
  own settings/profile screen — admin, teacher, and parent profile screens,
  plus the student's dedicated settings screen. Not a shared/drawer
  location.

## Bugs Found & Fixed

1. **Live-refresh not working** — `.tr()` alone doesn't register a locale
   dependency on already-pushed screens. Fix: add
   `context.watch<LocaleProvider>();` as the first line of every `build()`
   that renders translated text (including private State classes and
   helper widget classes reached via `Navigator.push`, `IndexedStack`, or
   `TabBarView`).
2. **Crash**: *"Tried to listen to an InheritedWidget in a life-cycle that
   will never be called again"* — caused by touching `context.locale`
   inside the `ChangeNotifierProvider`'s `create:` callback in
   `main.dart`. Fixed by keeping `LocaleProvider`'s constructor
   context-free.
3. **Ink/Material warning** ("ListTile background color or ink splashes
   may be invisible") — fixed by wrapping `ListTile`-containing `Column`s
   in `Material(type: MaterialType.transparency, clipBehavior:
   Clip.antiAlias)` (applied in `LanguageSelector` and several profile
   menu cards).
4. **Two text-overflow bugs** caused by longer Spanish strings (Admin
   Images header, a stats summary card) — fixed with `Expanded`/`Flexible`
   + `overflow: TextOverflow.ellipsis` (+`maxLines` where needed). This is
   now the standard pattern applied proactively anywhere Spanish text is
   likely to run longer than English (e.g. `_SummaryMetric` labels).

## Conventions Established

- **Key naming**: `'<namespace>.<file_or_screen_name>.<camelCaseKey>'.tr()`
  — `common.*` for shared/reusable strings (generic actions: Cancel,
  Delete, Edit, Save, Confirm, Add, Refresh, Retry, error-message
  templates, etc.); `teacher.<filename>.*` / `admin.<filename>.*` etc. for
  screen-specific strings, one sub-namespace **per source filename** (not
  per class name) — even when text repeats across files, each file
  generally gets its own key (per-file namespacing, not aggressive global
  dedup).
- **Interpolation**: `.tr(namedArgs: {'argName': '$value'})` with literal
  `{argName}` placeholders in the JSON value. Non-string values are
  stringified before passing.
- **Pluralization**: `.plural(count)` — JSON shape
  `{"one": "...", "other": "..."}`, `{}` marks the count position — used
  **only** for genuine count-based grammatical plurals, never for mode
  toggles (e.g. singular "Report" vs plural "Reports" button label is two
  separate keys, not `.plural()`, since it's driven by a filter state, not
  a count).
- **What's excluded from translation**: debug/log strings, code comments,
  Firestore field/document keys, asset paths, internal type/enum
  identifiers, and — a recurring judgment call — foreign-language example
  content inside hints (e.g. the Spanish sentence shown as an example in a
  Spanish-input field) is left as-is; only the "e.g."/"ej." wrapper is
  translated.
- **Data vs. chrome**: anything persisted to Firestore (bookmark titles,
  fallback content names) is treated as data and left untranslated to
  avoid baking a save-time locale into stored records.

## Scope Translated So Far

- **`lib/screens/initials/` activity-play flow (shared by teacher preview AND
  student real-play — `teacher_activity_screen.dart` launches
  `ActivityPlayScreen`/`QuizPlayScreen` with `isPreview: true`,
  `student_activities_screen.dart` launches the same screens for real play)**:
  `activity_play_screen.dart` (orchestrator: no-tasks/error dialogs,
  unimplemented-task-type fallback, review-round banner),
  `activity_complete_screen.dart` (celebration screen — `screenTitle` changed
  from a hardcoded constructor-default string to nullable, resolved via
  `.tr()` inside `build()` since default parameter values must be
  compile-time constants), and all 12 task-type screens (`screen_one.dart`
  through `screen_twelve.dart`). Also 5 shared widgets every task screen
  routes through: `widget/task_result_sheet.dart`,
  `widget/exit_task_dialog.dart` (quit confirmation),
  `widget/retryable_task.dart` (retry-prompt sheet),
  `widget/practice_round_intro_screen.dart` (parrot intro), and
  `lib/services/speech_to_text/speech_permissions.dart`'s mic-permission
  dialog. New `initials.<filename>.*` namespace per file (kept for
  `speech_permissions.dart` too, despite living under `services/`, since
  it's exclusively used from this flow). `screen_ten.dart` reuses several of
  `screen_nine.dart`'s keys directly (`initials.screen_nine.*`) for strings
  verbatim-duplicated between the two (mic-error/pronunciation-feedback
  text) rather than duplicating them under separate key names. A large
  number of `common.*` keys already existed unused before this pass and
  were simply wired up via `.tr()` (`common.check`, `common.continue`,
  `common.finish`, `common.tryAgain`, `common.score`, `common.correct`,
  `common.wrong`, `common.experienceEarned`, `common.backToMenu`,
  `common.noConversationData`, `common.yourReply`,
  `common.noOptionsAvailable`, `common.loadingTaskErr`, `common.noTask`,
  `common.activityTask`, `common.ok`, `common.error`,
  `common.activityComplete`, `common.notImplemented`, `common.skipTask`,
  `common.taskAvailability`). **`quiz_play_screen.dart`'s own chrome**
  (timer, quiz header, Previous/Next/Submit Quiz) is explicitly **not**
  covered — a deliberate follow-up gap; it still benefits indirectly since
  it reuses the 12 task screens and `ActivityCompleteScreen` translated
  here.
- **Admin role**: fully translated (dashboard, images, navigation, profile,
  upload/view image screens).
- **Teacher role**:
  - Chrome/navigation, teacher profile screen (full).
  - **Groups feature**: group card, group navigation + all 5 tabs.
  - **Quizzes**: filters, tags, Add Summative/Formative flows, delete
    dialog, plus the Create/Edit Quiz screen (Passing Score, XP Reward,
    Maximum Attempts, all fields/validation/buttons).
  - **Statistics tab**: unit filter, overflow-safe summary card
    (Students/Completion/Needs Attention), Details/Reports buttons, plus
    3 related screens: Student Detail Progress, Report Preview, Report
    History.
  - **Full content-authoring pipeline**: `teacher_content_editor_screen`,
    `create_content_screen`, `teacher_unit_editor_screen`,
    `create_unit_screen`, `teacher_lesson_editor_screen`,
    `create_lesson_screen`, `teacher_activity_editor_screen`,
    `create_activity_screen`, `teacher_task_editor_screen`,
    `create_task_screen` — all fully translated (operations, dialogs,
    validation, buttons).
  - **`lib/screens/teacher/widgets/*.dart`** (18 files) and
    **`lib/screens/teacher/task_types/*.dart`** (14 files) — fully
    translated, including the individual task-type editors (Match, Fill
    Blank, Arrange, Reading Comprehension, Sentence Builder, etc.).
    - `slow_reveal_task.dart` intentionally skipped — its entire body is
      commented-out dead code, nothing renders.
  - **Image library screens**: `teacher_image_screen.dart`,
    `teacher_view_images_screen.dart`, `teacher_upload_image_screen.dart` —
    fully translated (category CRUD dialogs, upload flow, delete
    confirmations, snackbars). The widgets they render
    (`TeacherEmptyState`, `TeacherCategoryCard`, `TeacherImageTile`,
    `TeacherPreviewSheet`, `TeacherIdleView`, `TeacherUploadingView`) were
    already translated as part of the `widgets/*.dart` pass above — only
    the three screen files themselves had the gap. Mirrors the admin
    `admin_images_screen.dart` / `admin_view_images_screen.dart` /
    `admin_upload_image_screen.dart` key structure 1:1 (teacher's upload
    screen has no `_maxImages` cap, so the admin-only max-related keys
    were not carried over).
  - **`teacher_league_screen.dart`** — fully translated (Ranking/Rewards
    tabs, empty states, reward-campaign form, snackbars). League tier
    names (`Starter`/`Bronze`/`Silver`/.../`Diamond`) come from the shared
    `kLeagueTiers` constant in `lib/models/league_tier.dart` (also used by
    `student_league_screen.dart`, untouched by this pass) — added a
    `tierLabel(key)` helper there, under a new shared
    `common.leagueTierNames.*` namespace, mirroring the
    `taskTypeLabel()`/`kTaskTypeGroups` pattern: the `name` field itself
    stays an untranslated stable key, `tierLabel()` maps it to display
    text. Tier `range` strings (e.g. "200 – 499 XP") are left as-is in
    both locales — numbers + the "XP" unit read as locale-neutral chrome.
  - **Follow-up fix**: the "Add Task" bottom sheet's category group
    headers (Vocabulary, Grammar, Reading, Speaking & Listening,
    Conversation) and task-type row labels in
    `task_type_selector_screen.dart` were rendering raw untranslated
    strings from `kTaskTypeGroups` instead of the translated lookups
    already defined in `task_type_option.dart`. Fixed by making
    `taskTypeLabel()`/`taskGroupLabel()` public in `task_type_option.dart`
    and reusing them from `task_type_selector_screen.dart`. Note:
    `kTaskTypeGroups`'s String keys/ids themselves stay untranslated on
    purpose — they're consumed as stable identifiers elsewhere (e.g.
    `parent_home_screen.dart`'s Skill Insights aggregation via
    `taskCategoryFor()`).
  - **`teacher_home_screen.dart`** (drawer, Create Group modal, empty/error
    states, biometric-resume reason) and **`archived_groups_screen.dart`**
    (empty state, "Back to My Groups") — fully translated.
  - **Notifications screen consolidated**: `lib/screens/parent/
    parent_notifications_screen.dart` (`ParentNotificationsScreen`) was
    already role-agnostic in practice — it just queries `notifications` by
    `userId`, and both `notifyOverdueActivities.ts` (teacher + parent) and
    `groupInvitationNotifications.ts` (parent only) write into that same
    collection/schema — but `teacher_home_screen.dart` was importing it
    directly from the parent folder. Moved it to
    `lib/screens/shared/notifications_screen.dart` as `NotificationsScreen`
    (deleted the old file), updated both the teacher and parent nav to
    import from there, and fully translated it under a new
    `components.notifications_screen.*` namespace (the `components.*` root
    key already existed in both translation files as an unused
    placeholder — this is its first real use, reserved for exactly this
    kind of role-agnostic shared screen/component text, as opposed to
    `common.*` which is for atomic reusable strings like button labels).

## Scope Translated So Far (cont'd)

- **Parent role — fully translated**: `parent_navigation_screen.dart` (drawer/tab
  labels, `_formatDate`'s month abbreviations — now looked up via 12 new
  `common.month*` keys instead of a hardcoded English list, delete-account
  dialog), `parent_home_screen.dart` (3 separate `build()` contexts: the
  screen itself, `_FollowUpsSectionState`, `_TaskInsightsSectionState`),
  `parent_children_screen.dart`, `parent_reports_screen.dart`,
  `parent_child_activity_status_screen.dart` (+ its own separate
  `_ActivityCard` widget), `parent_child_progress_path_screen.dart` (828
  lines — no single legend widget, status badges are inline per path-node),
  `child_report_detail_screen.dart`, `parent_join_group_screen.dart`,
  `parent_register_child_screen.dart`. Thrown `Exception(...)` messages that
  reach the user via a generic `catch (e) { ...'$e'... }` snackbar are
  translated at the throw site (e.g.
  `throw Exception('parent.parent_join_group_screen.invalidCode'.tr())`) so
  the existing wrapper still works unmodified.
  - `parent_profile_screen.dart` was already scaffolded for this — it had
    `context.watch<LocaleProvider>()` in all 3 of its build contexts (main
    state, an inline route-builder closure for Personal Data,
    `_SecurityScreen`) and `LanguageSelector` already wired in, just missing
    the `easy_localization` import and `.tr()` calls. A large number of
    `common.*` keys (e.g. `personalDataSubtitleParent`,
    `securitySubtitleParent`, `notificationSubtitleParent`) were already
    pre-seeded unused, matching this screen's strings exactly, and got
    reused rather than duplicated — same pattern seen across this whole
    parent-role pass (`common.myChildren`, `unknownGroup`,
    `noGroupAssigned`, `noChildRegistered`, `joinGroup`, `accessCode`,
    `reportsSubMsg`, `noReports`, `registerChildParent`,
    `studentAccessCode`, etc. all pre-existed unused).
  - Two small shared widgets translated along the way since each is reused
    by another role too (not scope creep — same reasoning as consolidating
    `NotificationsScreen` earlier): `lib/components/avatar_selector.dart`
    (shared with `student_settings_screen.dart`, namespace
    `components.avatar_selector.*`) and
    `lib/components/notification_permission_card.dart` (parent-only,
    namespace `parent.notification_permission_card.*`).
  - **Icon-only bottom tabs (parent only)**: `lib/components/app_bottom_nav_bar.dart`
    (shared with `student_main_screen.dart`) gained an opt-in `showLabels`
    bool, default `true`. `parent_navigation_screen.dart` passes
    `showLabels: false`; `student_main_screen.dart` now does too (see
    Student role below) — both roles' bottom tabs are icon-only, mirroring
    the teacher role's icon-only bottom tabs (`group_navigation_screen.dart`,
    done earlier this session), each via its own opt-in flag rather than
    changing the shared component's default.
  - **Out of scope**: `lib/utils/unit_report_pdf.dart` (reached from
    `child_report_detail_screen.dart`'s Export PDF button) — uses the `pw`
    package to render a PDF, not Flutter widgets, so `easy_localization`'s
    `.tr()` doesn't apply the same way. Its English strings ('Loringo Unit
    Report', 'Student:', 'Activity Details', etc.) remain untranslated; a
    follow-up if bilingual PDF export is wanted.
- **Student role — fully translated**: `student_main_screen.dart` (drawer +
  bottom-tab labels, `showLabels: false` — icon-only, same as parent/teacher),
  `student_code_screen.dart` (access-code login), `student_activities_screen.dart`
  (1009 lines — Firestore-missing-field fallbacks and status badges mirror
  the wording already established for the identical problem in
  `parent_child_progress_path_screen.dart`, but as separate
  `student.student_activities_screen.*` keys per this doc's per-file
  namespacing convention, not cross-role key references),
  `student_league_screen.dart` (616 lines — previously rendered
  `kLeagueTiers`' raw English `name` field directly at 3 sites, the exact
  pre-translation pattern `teacher_league_screen.dart` had; switched all 3
  to `tierLabel(tier['key'])` reusing `common.leagueTierNames.*`. Doing so
  surfaced a latent bug: `_buildLeagueTiersList`'s "is this the student's
  current tier" check compared `tier['name'] == currentLeagueName`, which
  would have silently broken once `name` became a translated display
  string — fixed to compare by the stable `key` instead), and
  `student_settings_screen.dart` (already had `context.watch<LocaleProvider>()`
  in place, same as `parent_profile_screen.dart` before it — just needed the
  import + `.tr()` wiring). Also `lib/screens/student/widgets/winner_banner.dart`
  (the "Prize:" banner). `lib/screens/student/widgets/league_stat_card.dart`
  needed no changes — `label` is passed in pre-translated by the caller.
  `lib/screens/student/student_group_screen.dart` exists but is never
  instantiated anywhere (dead code) — excluded.
- **Cross-role providers translated**: `lib/providers/biometric_provider.dart`
  and `lib/providers/notification_provider.dart` — these are `ChangeNotifier`
  classes, not widgets, so their dialogs/snackbars call `.tr()` directly with
  no `context.watch` needed (same reasoning as `confirmExitTask` and
  `speech_permissions.dart` earlier: an imperative call triggered by a user
  action reads whatever the current locale is, no live-rebuild concern).
  New `providers.biometric_provider.*` / `providers.notification_provider.*`
  namespace (new top-level `providers` root, alongside `common`/`components`).
- **`lib/screens/initials/reset_in_app_screen.dart` (Change Password)
  restructured**: previously a hardcoded solid-color `AppBar`, shared as-is
  across all 3 roles that reach it (parent/teacher/admin profile screens).
  Replaced with a `required Widget header` constructor param — each caller
  now passes its own role's screen-header widget
  (`ParentScreenHeader`/`TeacherScreenHeader`/`AdminScreenHeader`, each with
  `title: 'common.changePassword'.tr()`) instead of this screen owning one
  specific role's look. Fully translated under `initials.reset_in_app_screen.*`.

## Known Gaps / Not Yet Covered

- **`lib/screens/initials/quiz_play_screen.dart`** — deliberately excluded
  from the activity-play-flow pass above (own chrome: timer, quiz header,
  Previous/Next/Submit Quiz, Quiz Passed/Complete title). It reuses the 12
  now-translated task screens and `ActivityCompleteScreen`, so those
  portions already switch locale correctly inside a quiz — only this
  file's own ~800 lines of wrapper chrome remain English-only.
- Any teacher screens outside the explicitly listed ones above (if new
  screens exist or are added later) will need the same
  import/`context.watch`/`.tr()` treatment following the conventions above.

## Verification Pattern Used Throughout

1. `node -e "JSON.parse(fs.readFileSync(...))"` on both translation files
   after every edit — catches JSON corruption immediately.
2. `flutter analyze` on changed files, then a full-project
   `flutter analyze` — expect 0 errors; pre-existing `info`/`warning`
   level issues (mostly `withOpacity` deprecation) are unrelated and
   expected.
3. Manual check: toggle EN/ES from the relevant profile/settings screen
   and confirm on-screen text switches immediately without needing to
   navigate away and back.
