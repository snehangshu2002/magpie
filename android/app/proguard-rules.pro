# youtubedl-android maps yt-dlp's JSON onto its model classes with Jackson
# (reflection) and ships no consumer rules, so keep both intact under R8.
-keep class com.yausername.** { *; }
-keep class com.fasterxml.jackson.** { *; }
-keepattributes Signature,*Annotation*,EnclosingMethod,InnerClasses
-dontwarn com.fasterxml.jackson.databind.ext.**
