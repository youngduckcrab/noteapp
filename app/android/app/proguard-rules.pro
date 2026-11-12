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
