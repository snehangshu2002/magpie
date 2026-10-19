# youtubedl-android maps yt-dlp's JSON onto its model classes with Jackson
# (reflection) and ships no consumer rules, so keep both intact under R8.
-keep class com.yausername.** { *; }
-keep class com.fasterxml.jackson.** { *; }
-keepattributes Signature,*Annotation*,EnclosingMethod,InnerClasses
-dontwarn com.fasterxml.jackson.databind.ext.**

# It unpacks Python/FFmpeg with commons-compress, whose ZipExtraField
# registry instantiates classes by reflection ("class X is not a concrete
# class" at startup when R8 strips their constructors).
-keep class org.apache.commons.compress.** { *; }
-dontwarn org.apache.commons.compress.**
