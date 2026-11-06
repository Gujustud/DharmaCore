# Brother Print SDK — native JNI reads fields by name (e.g. JNIRasterParam.portId).
# R8 stripping those fields causes:
#   NoSuchFieldError: no "I" field "portId" in class JNIRasterParam
#   JNI DETECTED ERROR IN APPLICATION: fid == null in GetIntField / initJNI
-keep class com.brother.** { *; }
-keepclassmembers class com.brother.** { *; }
-keepnames class com.brother.** { *; }
-dontwarn com.brother.**

# Keep Flutter / Play Core bits that R8 sometimes warns about
-dontwarn com.google.android.play.core.**
