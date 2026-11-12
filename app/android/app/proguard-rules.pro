# Release R8 rules (Flutter adds this file to the release build when it exists).
#
# WorkManager's Room database is created by reflection (WorkDatabase_Impl,
# the Room-generated class): R8 removed its constructor and the release APK
# closed at launch with 'Failed to create an instance of
# androidx.work.impl.WorkDatabase' (android-emulator.yml run 43233521029,
# tool/android/release_launch_check.sh). Keep every Room database's generated
# implementation and its no-argument constructor.
-keep class * extends androidx.room.RoomDatabase { <init>(); }
-keep class androidx.work.impl.WorkDatabase_Impl { *; }

# ML Kit (google_mlkit_digital_ink_recognition — handwriting recognition)
# finds its component registrars by reflection and calls their no-argument
# constructors. R8 removed them: 'NoSuchMethodException:
# …DigitalInkRecognitionRegistrar.<init> []' and the plugin failed to register
# (android-emulator.yml run 43241551603). Keep every registrar's constructor.
-keep class * implements com.google.firebase.components.ComponentRegistrar { <init>(); }
-keep class com.google.mlkit.**.*Registrar { <init>(); }

# ONNX Runtime (flutter_onnxruntime — the on-device math engine): its JNI
# library looks up the Java classes (OrtSession, OnnxTensor, OrtException …)
# and their fields / constructors by name from native code, which R8 cannot
# see; the ONNX Runtime docs ask Android apps minified with R8 for exactly
# this rule (also the plugin's README). Keep the plugin's own classes too
# (registered by name in GeneratedPluginRegistrant).
-keep class ai.onnxruntime.** { *; }
-keep class com.masicai.flutteronnxruntime.** { *; }
