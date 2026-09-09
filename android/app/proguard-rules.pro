# Flutter specific
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# Keep Firebase classes
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**

# Keep Firebase Instance ID
-keep class com.google.firebase.iid.** { *; }
-dontwarn com.google.firebase.iid.**

# Ignore Play Core missing classes (Flutter deferred components)
-dontwarn com.google.android.play.core.**
-dontwarn com.google.android.play.core.splitcompat.**
-dontwarn com.google.android.play.core.splitinstall.**
-dontwarn com.google.android.play.core.tasks.**

# Keep Flutter's deferred component classes
-keep class io.flutter.embedding.engine.deferredcomponents.** { *; }
-keep class io.flutter.embedding.android.FlutterPlayStoreSplitApplication { *; }

# Don't let missing classes fail the build
-ignorewarnings
-dontwarn **

# Keep our app classes
-keep class com.example.loringo_app.** { *; }

# Keep generic classes
-keep class * extends androidx.lifecycle.ViewModel { *; }
-keep class * extends androidx.room.RoomDatabase { *; }