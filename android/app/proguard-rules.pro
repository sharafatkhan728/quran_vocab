# ── Firebase ──────────────────────────────────────────────────────────────────
# These rules are needed because R8 (running automatically in release builds)
# can strip Firebase SDK classes when no explicit keep rules exist.
# The firebase_* Flutter plugins ship their own consumer-rules.txt via their
# AARs, but adding these explicitly ensures nothing is lost on custom builds.

# Firebase core
-keep class com.google.firebase.** { *; }
-keep class com.google.firebase.components.** { *; }
-keep class com.google.firebase.provider.** { *; }

# Firebase App Check — Play Integrity provider
-keep class com.google.firebase.appcheck.** { *; }
-keep class com.google.firebase.appcheck.playintegrity.** { *; }
-keep class com.google.firebase.appcheck.internal.** { *; }

# Firebase Auth
-keep class com.google.firebase.auth.** { *; }

# Firebase Crashlytics
-keep class com.google.firebase.crashlytics.** { *; }

# Firebase Firestore
-keep class com.google.firebase.firestore.** { *; }

# Firebase Storage
-keep class com.google.firebase.storage.** { *; }

# Flutter plugin registrars (must not be stripped)
-keep class io.flutter.plugins.firebase.** { *; }

# Google Play services
-keep class com.google.android.gms.** { *; }
-keep class com.google.android.play.** { *; }

# Keep all public methods of FirebaseApp (used via reflection)
-keep public class com.google.firebase.FirebaseApp {
    public *;
}

# Keep FirebaseInitProvider (reads google-services.json at startup)
-keep class com.google.firebase.provider.FirebaseInitProvider {
    public *;
}

# ── Flutter / Dart ───────────────────────────────────────────────────────────
# Keep Flutter engine entry points and platform channel handlers.
-keep class io.flutter.** { *; }
-keep class androidx.** { *; }

# Keep Dart NativeAsset entry points
-keep class * extends io.flutter.embedding.engine.dart.DartExecutor {
    public *;
}

# ── Play Core / Split Install (Flutter embedded) ──────────────────────────────
# Flutter's PlayStoreDeferredComponentManager references these classes.
# The app doesn't depend on play-core directly, so R8 strips them —
# suppress the warnings rather than adding an unused dependency.
-dontwarn com.google.android.play.core.splitcompat.SplitCompatApplication
-dontwarn com.google.android.play.core.splitinstall.SplitInstallException
-dontwarn com.google.android.play.core.splitinstall.SplitInstallManager
-dontwarn com.google.android.play.core.splitinstall.SplitInstallManagerFactory
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest$Builder
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest
-dontwarn com.google.android.play.core.splitinstall.SplitInstallSessionState
-dontwarn com.google.android.play.core.splitinstall.SplitInstallStateUpdatedListener
-dontwarn com.google.android.play.core.tasks.OnFailureListener
-dontwarn com.google.android.play.core.tasks.OnSuccessListener
-dontwarn com.google.android.play.core.tasks.Task
