# Architectural Patterns

## State Management

- **App-wide state**: `provider` package, registered once at the root via `MultiProvider`
  in `lib/main.dart:58-61` (`ChangeNotifierProvider` for `BiometricProvider` and
  `NotificationProvider`, both in `lib/providers/`). Use this pattern only for state that
  genuinely needs to be shared across many unrelated screens (biometric lock status,
  notification badges/counts).
- **Screen-level state**: plain `StatefulWidget` + `setState`. There is no Bloc/Riverpod/
  GetX anywhere in the app — don't introduce one for a single screen's local state.
- **Data fetching in widgets**: `StreamBuilder`/`FutureBuilder` consuming Firestore streams
  directly from `Database` methods, e.g. `lib/screens/student/student_activities_screen.dart`,
  `lib/screens/teacher/quiz_management_screen.dart`. There is no repository/BLoC layer
  between the widget and `Database` — widgets call `Database` methods directly.

## Database Access Layer

- All Firestore reads/writes go through the single `Database` class in
  `lib/services/database/database.dart:8`. Screens never call
  `FirebaseFirestore.instance` directly for the app's core collections — they call a
  method on `Database` (e.g. `getUserStream`, `saveActivityCompletion`,
  `getPersonalizedContentStream`). When adding a new collection or query, add a method
  to this class rather than querying Firestore ad hoc from a screen.
- Naming convention within `Database`: `get*` returns a `Future`, `get*Stream` returns a
  `Stream`, `save*`/`create*`/`update*`/`delete*` are the mutating counterparts (see
  `lib/services/database/database.dart:32-33`, `:492-495` for the paired pattern).
- Exception: narrowly-scoped, single-purpose services are allowed to query Firestore
  directly instead of going through `Database`, as long as they wrap a single well-defined
  rule — see `lib/services/content/content_assignment_guard.dart:30-38`, which takes a
  `Database` instance in its constructor but queries `FirebaseFirestore.instance` directly
  for its one specific check (whether a group has student progress against a content).
  This is the exception, not the default — prefer extending `Database` first.

## Auth-Guard / Secured-Screen Pattern

- Screens that require confirmation before backing out (to avoid accidental logout or
  lost progress) are wrapped in `SecuredScreen` (`lib/widget/secured_screen.dart:6`), which
  intercepts the back gesture via `PopScope` and routes to `LogoutService`
  (`lib/services/logout/logout_service.dart`). The `isStudent` flag distinguishes the
  student logout flow (access-code session) from the regular Firebase Auth logout flow.
  Reuse this wrapper for any new top-level screen that needs guarded exit, rather than
  reimplementing `PopScope` logic locally.

## Role-Based Screen Organization

- Screens are partitioned by role under `lib/screens/{initials,parent,teacher,student,admin}/`
  rather than by feature. A feature that touches multiple roles (e.g. quizzes) has
  separate screens under each relevant role directory rather than one shared parameterized
  screen. Follow this when adding a new feature: create role-specific screens, not a
  single screen with role branching.
- Task types (the atomic unit inside an activity) each get their own
  `StatefulWidget` under `lib/screens/teacher/task_types/` (e.g. `FillBlankTask`,
  `MatchTask`, `ListenAndSpeakTask`, `ImageSelectTask` — see
  `lib/screens/teacher/task_types/fill_blank_task.dart:5`,
  `lib/screens/teacher/task_types/match_task.dart:33`), all conforming to
  `TaskTypeEditor` (`lib/screens/teacher/task_types/task_type_editor.dart:5`). Add new
  task types by creating a new file in this directory and implementing that interface,
  rather than branching inside an existing task widget.

## Content Assignment & Progress Locking

- Content (`content/{id}/units/.../activities/.../tasks`) is assigned to groups via the
  `assignedTo` array field, checked by `content_assignment_guard.dart`. Once any student
  in a group has progress against a content, that content cannot be unassigned from the
  group — this is an intentional hard product rule (documented in the file's header
  comments), not a bug to "fix" by relaxing the check.
- Student-group membership has two representations that must stay in sync conceptually
  but are used for different purposes: `students/{id}.groupId` (source of truth for
  "which students belong to this group", used for progress/assignment queries — see
  `content_assignment_guard.dart:48-51`) vs. `teacherGroups/{id}/students/{id}` (roster
  subcollection, used for group-membership UI like inviting/removing students). Don't
  assume these two are interchangeable when writing new queries.

## Cloud Functions Pattern

- All Cloud Functions are `onCall` (client-invoked) or `onSchedule` (cron) — there are no
  Firestore-triggered functions (`onDocumentWritten`, etc.) anywhere in `functions/src/`.
  New backend logic that reacts to client actions should generally be a new `onCall`
  function, following the existing per-concern module split (`email.ts`, `resetPassword.ts`,
  `notifications.ts`, `moderateImage.ts`, `generateReadingAudio.ts`,
  `scheduledNotifications.ts`) rather than one large handler file.
