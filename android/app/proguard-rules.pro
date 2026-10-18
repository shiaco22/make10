# R8 / ProGuard rules for the release build.
#
# AGP 9 runs R8 in full mode, where a plain `-keep class X` no longer implies
# that X's no-arg constructor survives. Room's own consumer rules keep the
# generated database classes without naming any members, so in a release build
# R8 removes `androidx.work.impl.WorkDatabase_Impl.<init>()`.
#
# WorkManager creates that database from `androidx.startup`, inside a
# ContentProvider that runs before Application.onCreate and before Flutter.
# With the constructor gone the process dies immediately, every launch:
#
#   java.lang.RuntimeException: Unable to get provider
#     androidx.startup.InitializationProvider
#   Caused by: Failed to create an instance of androidx.work.impl.WorkDatabase
#
# Nothing here uses WorkManager directly; it arrives with google_mobile_ads.
# The crash is therefore invisible in debug builds, which do not run R8, and
# shows up only in the signed bundle that goes to Play.
#
# Keeping the constructors is enough. Keeping whole packages with `{ *; }`
# also works and is what most write-ups suggest, but it switches off shrinking
# for those packages and grows the app for no further benefit.
-keep class * extends androidx.room.RoomDatabase { <init>(); }
-keep class * extends androidx.work.InputMerger { <init>(); }
