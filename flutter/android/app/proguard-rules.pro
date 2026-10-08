# Flutter-specific ProGuard rules.
# Flutter engine and Dart AOT code is shipped as native .so — no rules needed for app logic.

# Keep Flutter embedding classes
-keep class io.flutter.** { *; }
-keep class io.flutter.embedding.** { *; }
-dontwarn io.flutter.embedding.**

# Keep generated plugin registrant
-keep class io.flutter.plugins.** { *; }

# http package uses dart:mirrors indirectly via reflection on some paths — keep annotations
-keepattributes *Annotation*

# Suppress warnings for Kotlin internals
-dontwarn kotlin.**
-dontwarn kotlinx.**
