# Flutter's own engine classes are reached from native code, so R8 cannot see
# the references and would otherwise strip them.
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# flutter_secure_storage reaches the Android keystore through reflection.
-keep class androidx.security.crypto.** { *; }

# Suppress warnings for optional Play Core classes Flutter references but does
# not ship - deferred components are not used here.
-dontwarn com.google.android.play.core.**
